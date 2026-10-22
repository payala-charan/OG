# frozen_string_literal: true

module DatabaseTransfer
  # What a transfer would do, table by table, before anything is written.
  class Plan
    PlannedTable = Struct.new(:name, :role, :definition, :row_count, :blockers, :warnings, keyword_init: true) do
      def blocked?
        blockers.any?
      end
    end

    attr_reader :source_database, :target_database, :tables, :blockers, :warnings,
                :selected_tables, :fingerprint

    def initialize(source_database:, target_database:, selected_tables:, tables:, blockers:, warnings:, fingerprint:)
      @source_database = source_database
      @target_database = target_database
      @selected_tables = selected_tables
      @tables = tables
      @blockers = blockers
      @warnings = warnings
      @fingerprint = fingerprint
    end

    def transferable?
      tables.any? && blockers.empty? && tables.none?(&:blocked?)
    end

    def table_names
      tables.map(&:name)
    end

    def blocked_tables
      tables.select(&:blocked?)
    end

    def total_rows
      tables.sum { |table| table.row_count.to_i }
    end
  end
end
