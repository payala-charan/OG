class AddTrigramIndexesToAllTables < ActiveRecord::Migration[7.1]
  IGNORED_TABLES = %w[
    schema_migrations
    ar_internal_metadata
    active_storage_blobs
    active_storage_attachments
    active_storage_variant_records
  ]

  # Columns eligible for trigram indexing
  TEXT_TYPES = ["character varying", "text", "varchar"]

  def change
    # Iterate over all tables in the DB
    ActiveRecord::Base.connection.tables.each do |table|
      next if IGNORED_TABLES.include?(table)

      # Fetch all columns
      ActiveRecord::Base.connection.columns(table).each do |col|

        # Only text-based columns
        next unless TEXT_TYPES.include?(col.sql_type)

        # Add GIN + trigram index dynamically
        add_index table.to_sym, col.name.to_sym, using: :gin, opclass: :gin_trgm_ops,
                  name: "index_#{table}_on_#{col.name}_trgm"
      end
    end
  end
end
