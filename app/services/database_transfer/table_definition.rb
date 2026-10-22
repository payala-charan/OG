# frozen_string_literal: true

module DatabaseTransfer
  # The FAT definition of one public table, as PostgreSQL reports it.
  # Every SQL fragment here comes from pg_catalog functions, not from user input.
  TableDefinition = Struct.new(
    :name,
    :columns,
    :constraints,
    :foreign_keys,
    :indexes,
    :sequences,
    :unsupported,
    :warnings,
    keyword_init: true
  ) do
    def column_names
      columns.map(&:name)
    end

    # Names this table would create in the target schema: the table, its
    # sequences, its indexes, and the indexes behind PRIMARY KEY/UNIQUE/EXCLUDE.
    def relation_names
      [ name ] +
        sequences.map(&:name) +
        indexes.map(&:name) +
        constraints.select(&:index_backed?).map(&:name)
    end

    def fingerprint_data
      {
        name: name,
        columns: columns.map(&:to_h),
        constraints: constraints.map(&:to_h),
        foreign_keys: foreign_keys.map(&:to_h),
        indexes: indexes.map(&:to_h),
        sequences: sequences.map(&:to_h)
      }
    end
  end
end
