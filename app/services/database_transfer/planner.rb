# frozen_string_literal: true

require "digest"

module DatabaseTransfer
  # Turns a dependency analysis into a transfer plan: the selected tables plus
  # their required parents, in load order, each checked against OG.
  #
  # A transfer only ever creates new tables. Any name that already exists in
  # OG blocks the plan; existing OG tables are never altered or appended to.
  class Planner
    # Rails bookkeeping. Copying these would corrupt OG's migration state.
    PROTECTED_TABLES = %w[schema_migrations ar_internal_metadata].freeze

    def initialize(source: DatabaseTransfer::Source.new, target: DatabaseTransfer::Target.new,
                   schema_reader: nil)
      @source = source
      @target = target
      @schema_reader = schema_reader || DatabaseTransfer::SchemaReader.new(source: source)
    end

    # `catalog` answers existing_names for OG. The executor passes its locked
    # session so the check and the writes see the same state.
    def build(analysis, counts: {}, catalog: target)
      names = analysis.dependency_order
      definitions = schema_reader.read(names)
      existing = catalog.existing_names(names.flat_map { |name| definitions[name]&.relation_names || [ name ] })
      plan_names = names.to_set

      tables = names.map do |name|
        definition = definitions[name]
        Plan::PlannedTable.new(
          name: name,
          role: analysis.selected?(name) ? :selected : :required,
          definition: definition,
          row_count: counts[name],
          blockers: table_blockers(name, definition, existing, plan_names, catalog),
          warnings: Array(definition&.warnings)
        )
      end

      Plan.new(
        source_database: source.database_name,
        target_database: catalog.database_name,
        selected_tables: analysis.selected_tables,
        tables: tables,
        blockers: plan_blockers(analysis),
        warnings: plan_warnings(analysis),
        fingerprint: fingerprint_for(tables, catalog)
      )
    end

    private

    attr_reader :source, :target, :schema_reader

    def table_blockers(name, definition, existing, plan_names, catalog)
      return [ "#{name} is Rails bookkeeping and is never transferred." ] if PROTECTED_TABLES.include?(name)
      return [ "#{name} is no longer a table in #{source.database_name}." ] if definition.nil?

      blockers = []
      if existing.include?(name)
        # Its own indexes and sequences would clash too; the table is the part worth reporting.
        return [ "#{name} already exists in #{catalog.database_name}. Existing OG tables are never changed; " \
                 "drop or rename it in OG first if you want the FAT copy." ]
      end

      clashes = (definition.relation_names - [ name ]).select { |relation| existing.include?(relation) }
      if clashes.any?
        blockers << "#{catalog.database_name} already has objects named #{clashes.sort.join(', ')}."
      end

      definition.unsupported.each { |problem| blockers << "#{name} #{problem}." }

      definition.foreign_keys.each do |foreign_key|
        next if foreign_key.target_schema == "public" && plan_names.include?(foreign_key.target_table)

        blockers << "#{name}.#{foreign_key.name} points at #{foreign_key.target_schema}.#{foreign_key.target_table}, " \
                    "which is not part of this transfer."
      end
      blockers
    end

    def plan_blockers(analysis)
      blockers = []
      blockers << "Select at least one table." if analysis.dependency_order.empty?
      analysis.external_dependencies.each do |edge|
        next unless analysis.dependency_order.include?(edge.from_table)

        blockers << "#{edge.summary} points outside the public tables in #{source.database_name}."
      end
      blockers
    end

    def plan_warnings(analysis)
      warnings = []
      if analysis.referencing_tables.any?
        names = analysis.referencing_tables.map(&:name)
        warnings << "#{names.size} related table(s) are not included: #{names.join(', ')}. " \
                    "Check them and update the plan to transfer them too."
      end
      if analysis.cyclic?
        warnings << "These tables have circular foreign keys. Foreign keys are added after all rows are loaded, so this is safe."
      end
      warnings
    end

    # Changes if FAT's definition of any planned table changes, or if the
    # source or target database changes. Row counts are deliberately left out.
    def fingerprint_for(tables, catalog)
      payload = {
        source: source.database_name,
        target: catalog.database_name,
        schema: target.schema,
        tables: tables.map { |table| table.definition&.fingerprint_data || { name: table.name, missing: true } }
      }
      Digest::SHA256.hexdigest(JSON.generate(payload))
    end
  end
end
