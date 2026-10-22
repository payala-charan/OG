# frozen_string_literal: true

module DatabaseTransfer
  # Lists public FAT tables and counts their rows.
  #
  # Listing and counting share one read-only transaction so a caller that is
  # already inside a snapshot (the transfer) does not open another one.
  class TableDiscovery
    TABLES_SQL = <<~SQL.freeze
      SELECT tablename
      FROM pg_catalog.pg_tables
      WHERE schemaname = 'public'
      ORDER BY tablename
    SQL

    def initialize(source: DatabaseTransfer::Source.new)
      @source = source
    end

    def source_database
      source.database_name
    end

    def table_names
      read_table_names
    end

    # refresh is accepted by the dashboard. Counts are always read from FAT.
    def tables_with_counts(refresh: false)
      source.with_read_only do
        read_table_names.map { |name| { name: name, count: row_count(name) } }
      end
    end

    private

    attr_reader :source

    def read_table_names
      source.select_all(TABLES_SQL).filter_map { |row| row["tablename"].to_s.presence }.uniq.sort
    end

    def row_count(name)
      source.select_value("SELECT COUNT(*) FROM #{source.quote_public_table(name)}").to_i
    end
  end
end
