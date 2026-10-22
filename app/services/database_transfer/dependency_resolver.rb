# frozen_string_literal: true

module DatabaseTransfer
  # Walks PostgreSQL foreign keys.
  #
  # Outgoing keys (this table references another) are required parents and are
  # followed recursively. Incoming keys (another table references this one) are
  # reported separately, also recursively. Declared constraints are the only
  # source of relationships.
  class DependencyResolver
    FOREIGN_KEY_SQL = <<~SQL.freeze
      SELECT
        src.relname AS from_table,
        src_att.attname AS from_column,
        tgt_ns.nspname AS to_schema,
        tgt.relname AS to_table,
        tgt_att.attname AS to_column,
        con.conname AS constraint_name
      FROM pg_constraint con
      INNER JOIN pg_class src ON src.oid = con.conrelid
      INNER JOIN pg_namespace src_ns ON src_ns.oid = src.relnamespace
      INNER JOIN pg_class tgt ON tgt.oid = con.confrelid
      INNER JOIN pg_namespace tgt_ns ON tgt_ns.oid = tgt.relnamespace
      INNER JOIN LATERAL unnest(con.conkey) WITH ORDINALITY AS src_cols(attnum, ord) ON TRUE
      INNER JOIN LATERAL unnest(con.confkey) WITH ORDINALITY AS tgt_cols(attnum, ord)
        ON src_cols.ord = tgt_cols.ord
      INNER JOIN pg_attribute src_att
        ON src_att.attrelid = src.oid AND src_att.attnum = src_cols.attnum
      INNER JOIN pg_attribute tgt_att
        ON tgt_att.attrelid = tgt.oid AND tgt_att.attnum = tgt_cols.attnum
      WHERE con.contype = 'f'
        AND src_ns.nspname = 'public'
      ORDER BY src.relname, con.conname, src_cols.ord
    SQL

    def initialize(source: DatabaseTransfer::Source.new)
      @source = source
    end

    def resolve(table_names, known_tables:)
      known = Array(known_tables).map(&:to_s).uniq
      requested = Array(table_names).map(&:to_s).uniq
      selected = requested.select { |name| known.include?(name) }.sort
      ignored = (requested - selected).sort
      return DatabaseTransfer::Analysis.empty(ignored_tables: ignored) if selected.empty?

      edges = load_edges
      build_analysis(selected, known, ignored, edges)
    end

    private

    attr_reader :source

    def load_edges
      source.select_all(FOREIGN_KEY_SQL).filter_map { |row| edge_from(row) }
    end

    def edge_from(row)
      from_table = row["from_table"].to_s
      to_table = row["to_table"].to_s
      return if from_table.blank? || to_table.blank?

      DatabaseTransfer::Edge.new(
        from_table: from_table,
        from_column: row["from_column"].to_s,
        to_schema: row["to_schema"].to_s,
        to_table: to_table,
        to_column: row["to_column"].to_s,
        constraint_name: row["constraint_name"].to_s
      )
    end

    def build_analysis(selected, known, ignored, edges)
      known_set = known.to_set
      outgoing, incoming = index_edges(edges)
      required_set, required_reasons, required_parent, external = walk_required(selected, known_set, outgoing)
      referencing_set, referencing_reasons, referencing_parent = walk_referencing(
        selected, known_set, incoming, required_set, external
      )
      nodes = selected + required_set.to_a
      order, cyclic = dependency_order(nodes, outgoing)

      DatabaseTransfer::Analysis.new(
        selected_tables: selected,
        required_tables: dependency_list(required_set, required_reasons, required_parent, :required),
        referencing_tables: dependency_list(referencing_set, referencing_reasons, referencing_parent, :referencing),
        external_dependencies: sort_edges(external),
        dependency_order: order,
        cyclic: cyclic,
        ignored_tables: ignored,
        outgoing_edges: outgoing,
        incoming_edges: incoming
      )
    end

    def index_edges(edges)
      outgoing = {}
      incoming = {}
      edges.each do |edge|
        (outgoing[edge.from_table] ||= []) << edge
        (incoming[edge.to_table] ||= []) << edge unless edge.self_reference?
      end
      outgoing.each_value { |list| list.sort_by! { |edge| edge_sort_key(edge) } }
      incoming.each_value { |list| list.sort_by! { |edge| edge_sort_key(edge) } }
      [ outgoing, incoming ]
    end

    def walk_required(selected, known_set, outgoing)
      required = Set.new
      reasons = Hash.new { |hash, key| hash[key] = [] }
      parent_edge = {}
      external = []
      queue = selected.dup
      processed = Set.new

      until queue.empty?
        current = queue.shift
        next if processed.include?(current)

        processed.add(current)
        Array(outgoing[current]).each do |edge|
          if edge.self_reference?
            next
          elsif !known_target?(edge, known_set)
            remember(external, edge)
            next
          end

          target = edge.to_table
          remember(reasons[target], edge)
          next if selected.include?(target)

          parent_edge[target] ||= edge
          required.add(target)
          queue << target unless processed.include?(target)
        end
      end

      [ required, reasons, parent_edge, external ]
    end

    def walk_referencing(selected, known_set, incoming, required, external)
      referencing = Set.new
      reasons = Hash.new { |hash, key| hash[key] = [] }
      parent_edge = {}
      queue = selected.dup
      seen = selected.to_set

      until queue.empty?
        current = queue.shift
        Array(incoming[current]).each do |edge|
          child = edge.from_table
          unless known_set.include?(child)
            remember(external, edge)
            next
          end

          remember(reasons[child], edge)
          next if selected.include?(child) || required.include?(child)

          parent_edge[child] ||= edge
          referencing.add(child)
          next if seen.include?(child)

          seen.add(child)
          queue << child
        end
      end

      [ referencing, reasons, parent_edge ]
    end

    def dependency_list(names, reasons, parent_edge, direction)
      names.to_a.sort.map do |name|
        DatabaseTransfer::TableDependency.new(
          name: name,
          reasons: sort_edges(reasons[name]),
          chain: chain_for(name, parent_edge, direction),
          direction: direction
        )
      end
    end

    def chain_for(table_name, parent_edge, direction)
      chain = [ table_name ]
      guard = 0
      while guard < 100 && (edge = parent_edge[chain.first])
        hop = direction == :required ? edge.from_table : edge.to_table
        break if hop.blank? || chain.include?(hop)

        chain.unshift(hop)
        guard += 1
      end
      chain
    end

    # Parents come first. A cycle has no safe start, so those tables are appended
    # alphabetically and reported separately.
    def dependency_order(nodes, outgoing)
      node_set = nodes.to_set
      indegree = nodes.to_h { |name| [ name, 0 ] }
      children_of = Hash.new { |hash, key| hash[key] = [] }

      parent_child_pairs(outgoing, node_set).each do |parent, child|
        children_of[parent] << child
        indegree[child] += 1
      end

      ready = nodes.select { |name| indegree[name].zero? }.sort
      order = []
      until ready.empty?
        node = ready.shift
        order << node
        children_of[node].each do |child|
          indegree[child] -= 1
          next unless indegree[child].zero?

          ready << child
          ready.sort!
        end
      end

      cyclic = order.size < nodes.size
      [ order + (nodes - order).sort, cyclic ]
    end

    def parent_child_pairs(outgoing, node_set)
      pairs = Set.new
      outgoing.each do |from_table, edges|
        edges.each do |edge|
          next if edge.self_reference?
          next unless node_set.include?(from_table) && node_set.include?(edge.to_table)

          pairs << [ edge.to_table, from_table ]
        end
      end
      pairs
    end

    def known_target?(edge, known_set)
      edge.to_schema == "public" && known_set.include?(edge.to_table)
    end

    def remember(list, edge)
      list << edge unless list.any? { |existing| existing.identity == edge.identity }
    end

    def sort_edges(edges)
      Array(edges).sort_by { |edge| edge_sort_key(edge) }
    end

    def edge_sort_key(edge)
      [ edge.from_table, edge.from_column, edge.to_schema, edge.to_table, edge.constraint_name ]
    end
  end
end
