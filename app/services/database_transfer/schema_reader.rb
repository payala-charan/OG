# frozen_string_literal: true

module DatabaseTransfer
  # Reads table definitions for public FAT tables from pg_catalog.
  #
  # Anything the transfer cannot reproduce exactly (identity or generated
  # columns, custom types, partitions, inheritance, shared sequences) is
  # reported as unsupported so the plan blocks instead of guessing.
  class SchemaReader
    TABLES_SQL = <<~SQL.freeze
      SELECT
        c.relname AS table_name,
        c.relkind AS relkind,
        c.relispartition AS is_partition,
        c.relrowsecurity AS row_security,
        EXISTS (SELECT 1 FROM pg_inherits inh WHERE inh.inhrelid = c.oid) AS inherits,
        (SELECT COUNT(*) FROM pg_trigger tg WHERE tg.tgrelid = c.oid AND NOT tg.tgisinternal) AS trigger_count
      FROM pg_class c
      INNER JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind IN ('r', 'p')
      ORDER BY c.relname
    SQL

    COLUMNS_SQL = <<~SQL.freeze
      SELECT
        c.relname AS table_name,
        a.attname AS column_name,
        format_type(a.atttypid, a.atttypmod) AS data_type,
        a.attnotnull AS not_null,
        pg_get_expr(d.adbin, d.adrelid) AS default_sql,
        a.attidentity AS identity,
        a.attgenerated AS generated,
        CASE
          WHEN t.typelem <> 0 THEN elem_ns.nspname
          ELSE type_ns.nspname
        END AS type_schema
      FROM pg_attribute a
      INNER JOIN pg_class c ON c.oid = a.attrelid
      INNER JOIN pg_namespace n ON n.oid = c.relnamespace
      INNER JOIN pg_type t ON t.oid = a.atttypid
      INNER JOIN pg_namespace type_ns ON type_ns.oid = t.typnamespace
      LEFT JOIN pg_type elem ON elem.oid = t.typelem
      LEFT JOIN pg_namespace elem_ns ON elem_ns.oid = elem.typnamespace
      LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE n.nspname = 'public'
        AND c.relkind IN ('r', 'p')
        AND a.attnum > 0
        AND NOT a.attisdropped
      ORDER BY c.relname, a.attnum
    SQL

    CONSTRAINTS_SQL = <<~SQL.freeze
      SELECT
        c.relname AS table_name,
        con.conname AS constraint_name,
        con.contype AS kind,
        pg_get_constraintdef(con.oid) AS definition,
        tgt_ns.nspname AS target_schema,
        tgt.relname AS target_table
      FROM pg_constraint con
      INNER JOIN pg_class c ON c.oid = con.conrelid
      INNER JOIN pg_namespace n ON n.oid = c.relnamespace
      LEFT JOIN pg_class tgt ON tgt.oid = con.confrelid
      LEFT JOIN pg_namespace tgt_ns ON tgt_ns.oid = tgt.relnamespace
      WHERE n.nspname = 'public'
        AND con.contype IN ('p', 'u', 'c', 'x', 'f')
      ORDER BY c.relname, con.conname
    SQL

    # Indexes that are not created by a PRIMARY KEY, UNIQUE or EXCLUDE constraint.
    INDEXES_SQL = <<~SQL.freeze
      SELECT
        c.relname AS table_name,
        ic.relname AS index_name,
        pg_get_indexdef(i.indexrelid) AS definition
      FROM pg_index i
      INNER JOIN pg_class c ON c.oid = i.indrelid
      INNER JOIN pg_class ic ON ic.oid = i.indexrelid
      INNER JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND c.relkind IN ('r', 'p')
        AND NOT EXISTS (
          SELECT 1
          FROM pg_constraint con
          WHERE con.conindid = i.indexrelid
            AND con.conrelid = i.indrelid
            AND con.contype IN ('p', 'u', 'x')
        )
      ORDER BY c.relname, ic.relname
    SQL

    # Sequences owned by a column (serial / bigserial), not identity sequences.
    SEQUENCES_SQL = <<~SQL.freeze
      SELECT
        t.relname AS table_name,
        a.attname AS column_name,
        s.relname AS sequence_name,
        format_type(seq.seqtypid, NULL) AS data_type,
        seq.seqstart AS start_value,
        seq.seqincrement AS increment_by,
        seq.seqmin AS min_value,
        seq.seqmax AS max_value,
        seq.seqcache AS cache_size,
        seq.seqcycle AS cycle
      FROM pg_class s
      INNER JOIN pg_namespace sn ON sn.oid = s.relnamespace
      INNER JOIN pg_sequence seq ON seq.seqrelid = s.oid
      INNER JOIN pg_depend dep
        ON dep.objid = s.oid
        AND dep.classid = 'pg_class'::regclass
        AND dep.refclassid = 'pg_class'::regclass
        AND dep.deptype = 'a'
      INNER JOIN pg_class t ON t.oid = dep.refobjid
      INNER JOIN pg_namespace tn ON tn.oid = t.relnamespace
      INNER JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = dep.refobjsubid
      WHERE s.relkind = 'S'
        AND sn.nspname = 'public'
        AND tn.nspname = 'public'
      ORDER BY t.relname, s.relname
    SQL

    BUILT_IN_TYPE_SCHEMAS = %w[pg_catalog].freeze

    def initialize(source: DatabaseTransfer::Source.new)
      @source = source
    end

    # Returns { table_name => TableDefinition } for the requested tables.
    # Names that are not public tables are left out.
    def read(table_names)
      wanted = Array(table_names).map(&:to_s).to_set
      return {} if wanted.empty?

      source.with_read_only do
        tables = rows(TABLES_SQL, wanted)
        columns = rows(COLUMNS_SQL, wanted).group_by { |row| row["table_name"] }
        constraints = rows(CONSTRAINTS_SQL, wanted).group_by { |row| row["table_name"] }
        indexes = rows(INDEXES_SQL, wanted).group_by { |row| row["table_name"] }
        sequences = rows(SEQUENCES_SQL, wanted).group_by { |row| row["table_name"] }

        tables.to_h do |table|
          name = table["table_name"]
          [
            name,
            build_definition(
              table,
              Array(columns[name]),
              Array(constraints[name]),
              Array(indexes[name]),
              Array(sequences[name])
            )
          ]
        end
      end
    end

    private

    attr_reader :source

    # Catalog queries read every public table; filtering happens here so no
    # table name is ever interpolated into SQL.
    def rows(sql, wanted)
      source.select_all(sql).to_a.select { |row| wanted.include?(row["table_name"].to_s) }
    end

    def build_definition(table, column_rows, constraint_rows, index_rows, sequence_rows)
      name = table["table_name"]
      sequences = sequence_rows.map { |row| sequence_from(row) }
      owned_columns = sequences.to_h { |sequence| [ sequence.column_name, sequence.name ] }
      unsupported = table_problems(table)
      warnings = table_warnings(table)

      columns = column_rows.map do |row|
        unsupported.concat(column_problems(row, owned_columns))
        ColumnDefinition.new(
          name: row["column_name"],
          data_type: row["data_type"],
          not_null: truthy?(row["not_null"]),
          default_sql: row["default_sql"].presence
        )
      end

      constraints = constraint_rows.map { |row| constraint_from(row) }

      TableDefinition.new(
        name: name,
        columns: columns,
        constraints: constraints.reject { |constraint| constraint.kind == "f" },
        foreign_keys: constraints.select { |constraint| constraint.kind == "f" },
        indexes: index_rows.map { |row| IndexDefinition.new(name: row["index_name"], definition: row["definition"]) },
        sequences: sequences,
        unsupported: unsupported,
        warnings: warnings
      )
    end

    def table_problems(table)
      problems = []
      problems << "is a partitioned table" if table["relkind"] == "p"
      problems << "is a partition of another table" if truthy?(table["is_partition"])
      problems << "inherits from another table" if truthy?(table["inherits"])
      problems
    end

    def table_warnings(table)
      warnings = []
      triggers = table["trigger_count"].to_i
      warnings << "#{triggers} trigger(s) are not copied" if triggers.positive?
      warnings << "row-level security policies are not copied" if truthy?(table["row_security"])
      warnings
    end

    def column_problems(row, owned_columns)
      column = row["column_name"]
      problems = []
      problems << "column #{column} is an identity column" if row["identity"].present?
      problems << "column #{column} is a generated column" if row["generated"].present?
      unless BUILT_IN_TYPE_SCHEMAS.include?(row["type_schema"])
        problems << "column #{column} uses custom type #{row["data_type"]}"
      end

      default_sql = row["default_sql"].to_s
      if default_sql.include?("nextval(")
        owned = owned_columns[column]
        unless owned && default_sql.include?("'#{owned}'")
          problems << "column #{column} uses a sequence it does not own"
        end
      end
      problems
    end

    def constraint_from(row)
      ConstraintDefinition.new(
        name: row["constraint_name"],
        kind: row["kind"],
        definition: row["definition"],
        target_schema: row["target_schema"].presence,
        target_table: row["target_table"].presence
      )
    end

    def sequence_from(row)
      SequenceDefinition.new(
        name: row["sequence_name"],
        column_name: row["column_name"],
        data_type: row["data_type"],
        start_value: row["start_value"].to_i,
        increment_by: row["increment_by"].to_i,
        min_value: row["min_value"].to_i,
        max_value: row["max_value"].to_i,
        cache_size: row["cache_size"].to_i,
        cycle: truthy?(row["cycle"])
      )
    end

    def truthy?(value)
      value == true || value.to_s == "t" || value.to_s == "true"
    end
  end
end
