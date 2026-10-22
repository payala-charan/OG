# frozen_string_literal: true

class FakeDatabaseTransferSource
  attr_reader :statements

  def initialize(database: "sep_22", tables: [], counts: {}, foreign_keys: [])
    @database = database
    @tables = tables
    @counts = counts
    @foreign_keys = foreign_keys
    @statements = []
  end

  def database_name
    @database
  end

  def with_read_only
    yield
  end

  def select_all(sql)
    @statements << sql
    if sql.include?("pg_catalog.pg_tables")
      @tables.map { |name| { "tablename" => name } }
    elsif sql.include?("pg_constraint")
      @foreign_keys
    else
      raise "Unexpected SQL: #{sql}"
    end
  end

  def select_value(sql)
    @statements << sql
    name = sql[/FROM "public"\."((?:[^"]|"")*)"/, 1]
    raise "Could not read table from #{sql}" if name.nil?

    @counts.fetch(name.gsub('""', '"'))
  end

  def quote_public_table(name)
    quoted = name.to_s.gsub('"', '""')
    %("public"."#{quoted}")
  end
end
