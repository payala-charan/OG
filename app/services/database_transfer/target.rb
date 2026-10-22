# frozen_string_literal: true

module DatabaseTransfer
  # Gateway to the OG primary database, the only place a transfer may write.
  #
  # Writes run on a connection checked out for the transfer alone. The run log
  # keeps using the normal Active Record connection, so progress stays visible
  # while the transfer transaction is still open.
  class Target
    # Arbitrary but fixed: one transfer at a time per OG database.
    LOCK_KEY = 4_723_901_115
    LOCK_TIMEOUT = "10s"

    attr_reader :schema

    def initialize(record_class: ApplicationRecord, schema: "public")
      @record_class = record_class
      @schema = schema.to_s
    end

    def database_name
      record_class.connection_db_config.database
    end

    # Names in `names` that already exist in the target schema as a relation
    # (table, index, sequence, view) or as a type.
    def existing_names(names)
      read_connection { |conn| self.class.lookup_names(conn, schema, names) }
    end

    def self.lookup_names(conn, schema, names)
      list = Array(names).map(&:to_s).uniq
      return Set.new if list.empty?

      values = list.map { |name| conn.quote(name) }.join(", ")
      schema_value = conn.quote(schema)
      relations = conn.select_values(<<~SQL)
        SELECT c.relname
        FROM pg_class c
        INNER JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = #{schema_value} AND c.relname IN (#{values})
      SQL
      types = conn.select_values(<<~SQL)
        SELECT t.typname
        FROM pg_type t
        INNER JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = #{schema_value} AND t.typname IN (#{values})
      SQL
      (relations + types).to_set
    end

    # Yields a Session inside a single transaction on a dedicated connection.
    # Raises LockUnavailable if another transfer holds the lock.
    def transaction
      pool = record_class.connection_pool
      conn = pool.checkout
      begin
        conn.transaction(requires_new: true) do
          session = Session.new(conn, schema)
          session.prepare!
          yield session
        end
      ensure
        pool.checkin(conn)
      end
    end

    def clear_schema_cache
      record_class.connection_pool.schema_cache.clear!
    rescue StandardError
      nil
    end

    private

    attr_reader :record_class

    def read_connection(&block)
      record_class.connection_pool.with_connection(&block)
    end

    class LockUnavailable < StandardError; end

    # Everything the executor can do to OG. Identifiers are always quoted here.
    class Session
      attr_reader :schema

      def initialize(conn, schema)
        @conn = conn
        @schema = schema
      end

      def prepare!
        conn.execute("SET LOCAL lock_timeout = #{conn.quote(LOCK_TIMEOUT)}")
        # FAT definitions name tables and sequences without a schema; resolve them in the target.
        search_path = [ quote_identifier(schema), (quote_identifier("public") unless schema == "public") ].compact.join(", ")
        conn.execute("SET LOCAL search_path TO #{search_path}")
        locked = conn.select_value("SELECT pg_try_advisory_xact_lock(#{LOCK_KEY})")
        raise LockUnavailable, "Another database transfer is running. Try again when it finishes." unless locked
      end

      def database_name
        conn.pool.db_config.database
      end

      def existing_names(names)
        Target.lookup_names(conn, schema, names)
      end

      def execute(sql)
        conn.execute(sql)
      end

      def select_value(sql)
        conn.select_value(sql)
      end

      def select_values(sql)
        conn.select_values(sql)
      end

      def qualified(name)
        "#{quote_identifier(schema)}.#{quote_identifier(name)}"
      end

      def quote_identifier(name)
        conn.quote_table_name(name.to_s)
      end

      def quote(value)
        conn.quote(value)
      end

      # Feeds rows in COPY text format into the table. Returns the row count.
      def copy_into(table_name, column_names)
        columns = column_names.map { |name| quote_identifier(name) }.join(", ")
        raw = conn.raw_connection
        count = 0
        raw.copy_data("COPY #{qualified(table_name)} (#{columns}) FROM STDIN") do
          yield(lambda do |row|
            raw.put_copy_data(row)
            count += 1
          end)
        end
        count
      end

      private

      attr_reader :conn
    end
  end
end
