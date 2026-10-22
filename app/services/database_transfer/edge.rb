# frozen_string_literal: true

module DatabaseTransfer
  # One foreign-key column pair discovered from PostgreSQL.
  Edge = Struct.new(
    :from_table,
    :from_column,
    :to_schema,
    :to_table,
    :to_column,
    :constraint_name,
    keyword_init: true
  ) do
    def self_reference?
      from_table == to_table && to_schema == "public"
    end

    def target_name
      to_schema == "public" ? to_table : "#{to_schema}.#{to_table}"
    end

    def summary
      "#{from_table}.#{from_column} → #{target_name}.#{to_column}"
    end

    def identity
      [ constraint_name, from_table, from_column, to_schema, to_table, to_column ]
    end
  end
end
