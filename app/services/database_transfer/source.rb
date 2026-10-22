# frozen_string_literal: true

module DatabaseTransfer
  # Read-only gateway to the FAT connection.
  # The database name comes from the connection config (FAT_DATABASE, default oct_5).
  class Source
    READ_ERRORS = [
      ActiveRecord::NoDatabaseError,
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::StatementInvalid,
      ActiveRecord::AdapterNotSpecified,
      PG::Error
    ].freeze

    def self.read_error?(error)
      READ_ERRORS.any? { |klass| error.is_a?(klass) }
    end

    def initialize(record_class: FatRecord)
      @record_class = record_class
    end

    def database_name
      record_class.connection_db_config.database
    end

    def with_read_only
      return yield if connection.transaction_open?

      connection.transaction do
        connection.execute("SET LOCAL transaction_read_only = on")
        yield
      end
    end

    # One read-only REPEATABLE READ transaction, so every table is read from the
    # same point in time even if FAT is being written to during the transfer.
    def with_snapshot
      raise ArgumentError, "FAT snapshot must not be nested in another transaction" if connection.transaction_open?

      connection.transaction(isolation: :repeatable_read) do
        connection.execute("SET LOCAL transaction_read_only = on")
        yield
      end
    end

    # Streams rows in PostgreSQL COPY text format. Only a whole public table can
    # be copied, and only inside a read-only transaction.
    def copy_rows(table_name, column_names)
      raise ArgumentError, "FAT copy needs an open read-only transaction" unless connection.transaction_open?
      raise ArgumentError, "FAT copy needs at least one column" if column_names.empty?

      columns = column_names.map { |name| quote_identifier(name) }.join(", ")
      sql = "COPY #{quote_public_table(table_name)} (#{columns}) TO STDOUT"
      raw = connection.raw_connection
      raw.copy_data(sql) do
        while (row = raw.get_copy_data)
          yield row
        end
      end
    end

    def select_all(sql)
      assert_select!(sql)
      run_read_only { connection.select_all(sql) }
    end

    def select_value(sql)
      assert_select!(sql)
      run_read_only { connection.select_value(sql) }
    end

    def quote_public_table(name)
      "#{quote_identifier("public")}.#{quote_identifier(name)}"
    end

    private

    attr_reader :record_class

    def connection
      record_class.connection
    end

    def quote_identifier(name)
      connection.quote_table_name(name.to_s)
    end

    def run_read_only
      if connection.transaction_open?
        yield
      else
        with_read_only { yield }
      end
    end

    def assert_select!(sql)
      statement = sql.to_s.lstrip
      unless statement.match?(/\ASELECT\b/i)
        raise ArgumentError, "FAT source only accepts SELECT statements"
      end
      return unless unquoted_semicolon?(statement)

      raise ArgumentError, "FAT source only accepts a single SELECT statement"
    end

    def unquoted_semicolon?(sql)
      in_quote = false
      sql.each_char do |char|
        if char == '"'
          in_quote = !in_quote
          next
        end
        return true if char == ";" && !in_quote
      end
      false
    end
  end
end
