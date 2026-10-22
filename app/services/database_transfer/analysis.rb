# frozen_string_literal: true

module DatabaseTransfer
  # Result of a dependency analysis. Nothing here writes to either database.
  class Analysis
    attr_reader :selected_tables, :required_tables, :referencing_tables,
                :external_dependencies, :dependency_order, :ignored_tables

    def self.empty(ignored_tables: [])
      new(
        selected_tables: [],
        required_tables: [],
        referencing_tables: [],
        external_dependencies: [],
        dependency_order: [],
        cyclic: false,
        ignored_tables: ignored_tables,
        outgoing_edges: {},
        incoming_edges: {}
      )
    end

    def initialize(selected_tables:, required_tables:, referencing_tables:, external_dependencies:,
                   dependency_order:, cyclic:, ignored_tables:, outgoing_edges:, incoming_edges:)
      @selected_tables = selected_tables
      @required_tables = required_tables
      @referencing_tables = referencing_tables
      @external_dependencies = external_dependencies
      @dependency_order = dependency_order
      @cyclic = cyclic
      @ignored_tables = ignored_tables
      @outgoing_edges = outgoing_edges
      @incoming_edges = incoming_edges
    end

    def cyclic?
      @cyclic
    end

    def selected?(name)
      selected_tables.include?(name)
    end

    def required?(name)
      required_tables.any? { |table| table.name == name }
    end

    def referencing?(name)
      referencing_tables.any? { |table| table.name == name }
    end

    def status_for(name)
      return :selected if selected?(name)
      return :required if required?(name)
      return :referencing if referencing?(name)

      nil
    end

    def tree_for(table_name)
      walk_tree(table_name, @outgoing_edges, :to_table, Set.new)
    end

    def referencing_tree_for(table_name)
      walk_tree(table_name, @incoming_edges, :from_table, Set.new)
    end

    private

    def walk_tree(table_name, grouped, child_method, seen)
      return [] if seen.include?(table_name)

      next_seen = seen | Set[table_name]
      Array(grouped[table_name]).map do |edge|
        child = edge.public_send(child_method)
        if edge.self_reference?
          node(edge, children: [], cycle: false, self_reference: true)
        elsif next_seen.include?(child)
          node(edge, children: [], cycle: true, self_reference: false)
        else
          node(
            edge,
            children: walk_tree(child, grouped, child_method, next_seen),
            cycle: false,
            self_reference: false
          )
        end
      end
    end

    def node(edge, children:, cycle:, self_reference:)
      { edge: edge, children: children, cycle: cycle, self_reference: self_reference }
    end
  end
end
