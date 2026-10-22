# frozen_string_literal: true

module DatabaseTransfer
  # Writes the Rails migration for tables a committed transfer created.
  #
  # The executor has already created the tables, so the version is recorded in
  # schema_migrations and is not run again. schema.rb is updated so a later
  # schema load recreates the columns, indexes, and foreign keys.
  class MigrationWriter
    TABLE_MARKER = "database_transfer:table:%s"
    FOREIGN_KEY_MARKER = "database_transfer:foreign_key:%s"

    def self.record!(run, connection: ApplicationRecord.connection, root: Rails.root, record_in_schema: true)
      new(run, connection:, root:, record_in_schema:).record!
    end

    def self.revert!(run, connection: ApplicationRecord.connection, root: Rails.root, record_in_schema: true)
      new(run, connection:, root:, record_in_schema:).revert!
    end

    def initialize(run, connection:, root:, record_in_schema:)
      @run = run
      @connection = connection
      @root = Pathname(root)
      @record_in_schema = record_in_schema
    end

    def record!
      return run.summary["migration_version"] if run.summary["migration_version"].present?

      tables = existing_tables
      return if tables.empty?

      version = nil
      fragments = dump_fragments(tables)
      version = next_version
      write_migration(version, fragments)
      record_version(version) if record_in_schema
      write_schema(version, fragments) if record_in_schema
      run.update!(summary: run.summary.merge("migration_version" => version, "migration_tables" => tables))
      version
    rescue StandardError
      cleanup_failed_record(version)
      raise
    end

    def revert!
      version = run.summary["migration_version"].presence
      tables = Array(run.summary["migration_tables"].presence || run.planned_tables).map(&:to_s)
      return if version.blank?

      path = migration_path(version)
      File.delete(path) if path.exist?
      if record_in_schema
        connection.execute("DELETE FROM schema_migrations WHERE version = #{connection.quote(version)}")
        remove_from_schema(tables)
      end
      run.update!(summary: run.summary.except("migration_version", "migration_tables"))
    end

    private

    attr_reader :run, :connection, :root, :record_in_schema

    def existing_tables
      present = connection.tables
      Array(run.planned_tables).map(&:to_s).select { |name| present.include?(name) }.uniq.sort
    end

    def dump_fragments(table_names)
      dumper = connection.create_schema_dumper(table_name_prefix: "", table_name_suffix: "")
      tables = {}
      foreign_keys = {}
      table_names.each do |name|
        body = StringIO.new
        dumper.send(:table, name, body)
        dumped = trim_blank_lines(body.string)
        raise "Could not dump #{name}" if dumped.blank? || dumped.lstrip.start_with?("# Could not dump")

        tables[name] = dumped
        keys = StringIO.new
        dumper.send(:foreign_keys, name, keys)
        statement = trim_blank_lines(keys.string)
        foreign_keys[name] = statement if statement.present?
      end
      { tables: tables, foreign_keys: foreign_keys }
    end

    def write_migration(version, fragments)
      migrations_directory.mkpath
      migration_path(version).write(migration_source(version, fragments))
    end

    def migration_source(version, fragments)
      statements = creation_order(fragments).map { |name| migration_table(name, fragments[:tables][name]) }
      statements.concat(fragments[:foreign_keys].keys.sort.map { |name| migration_foreign_key(fragments[:foreign_keys][name]) })
      <<~RUBY
        # frozen_string_literal: true

        class TransferFatTablesRun#{run.id} < ActiveRecord::Migration[#{ActiveRecord::Migration.current_version}]
          def change
        #{statements.join("\n\n")}
          end
        end
      RUBY
    end

    def migration_table(name, dumped)
      dumped
        .sub("create_table \"#{name}\", force: :cascade", "create_table :#{name}")
        .gsub(/^/, "  ")
    end

    def migration_foreign_key(statement)
      statement.gsub(/"([^"]+)"/, ':\\1').gsub(/^/, "  ")
    end

    def creation_order(fragments)
      referenced = fragments[:foreign_keys].values.filter_map { |statement| statement[/add_foreign_key "[^"]+", "([^"]+)"/, 1] }
      names = fragments[:tables].keys
      ((names & referenced).sort + (names - referenced).sort).uniq
    end

    def write_schema(version, fragments)
      schema = schema_path.read
      lines = schema.lines
      fragments[:tables].each_key { |name| lines = remove_marker(lines, format(TABLE_MARKER, name)) }
      fragments[:foreign_keys].each_key { |name| lines = remove_marker(lines, format(FOREIGN_KEY_MARKER, name)) }
      fragments[:tables].keys.sort.each do |name|
        lines = insert_table(lines, name, fragments[:tables][name])
      end
      fragments[:foreign_keys].keys.sort.each do |name|
        lines = insert_foreign_key(lines, name, fragments[:foreign_keys][name])
      end
      updated = lines.join.sub(/\.define\(version: [^)]+\)/, ".define(version: #{formatted_version(version)})")
      schema_path.write(updated)
    end

    def insert_table(lines, name, dumped)
      block = marker_lines(format(TABLE_MARKER, name), dumped, blank_line: true)
      index = lines.index { |line| (match = line.match(/^  create_table "([^"]+)"/)) && match[1] > name }
      index ||= lines.rindex { |line| line.strip == "end" } || lines.length
      lines.insert(index, *block)
    end

    def insert_foreign_key(lines, name, statement)
      block = marker_lines(format(FOREIGN_KEY_MARKER, name), statement, blank_line: false)
      index = lines.index { |line| (match = line.match(/^  add_foreign_key "([^"]+)"/)) && match[1] > name }
      index ||= lines.rindex { |line| line.strip == "end" } || lines.length
      lines.insert(index, *block)
    end

    def marker_lines(marker, body, blank_line:)
      content = body.to_s.each_line.map { |line| line.end_with?("\n") ? line : "#{line}\n" }
      content << "\n" if blank_line
      [ "  # #{marker}\n", *content, "  # /#{marker}\n" ]
    end

    def trim_blank_lines(text)
      text.to_s.sub(/\A\n+/, "").sub(/\s+\z/, "")
    end

    def remove_from_schema(table_names)
      return unless schema_path.exist?

      lines = schema_path.readlines
      table_names.each do |name|
        lines = remove_marker(lines, format(TABLE_MARKER, name))
        lines = remove_marker(lines, format(FOREIGN_KEY_MARKER, name))
      end
      version = connection.select_value("SELECT MAX(version) FROM schema_migrations")
      updated = lines.join
      updated = updated.sub(/\.define\(version: [^)]+\)/, ".define(version: #{formatted_version(version)})") if version.present?
      schema_path.write(updated)
    end

    def remove_marker(lines, marker)
      start_marker = /# #{Regexp.escape(marker)}\s*\z/
      end_marker = %r{# /#{Regexp.escape(marker)}\s*\z}
      skipping = false
      lines.each_with_object([]) do |line, kept|
        if line.match?(start_marker)
          skipping = true
          next
        end
        if skipping
          skipping = false if line.match?(end_marker)
          next
        end
        kept << line
      end
    end

    def record_version(version)
      quoted = connection.quote(version)
      return if connection.select_value("SELECT 1 FROM schema_migrations WHERE version = #{quoted}")

      connection.execute("INSERT INTO schema_migrations (version) VALUES (#{quoted})")
    end

    def cleanup_failed_record(version)
      return if version.blank?

      path = migration_path(version)
      File.delete(path) if path.exist?
      return unless record_in_schema

      connection.execute("DELETE FROM schema_migrations WHERE version = #{connection.quote(version)}")
    rescue StandardError
      nil
    end

    def next_version
      stamp = Time.current.utc.strftime("%Y%m%d%H%M%S")
      stamp = stamp.succ while migration_path(stamp).exist? || version_recorded?(stamp)
      stamp
    end

    def version_recorded?(version)
      return false unless record_in_schema

      connection.select_value("SELECT 1 FROM schema_migrations WHERE version = #{connection.quote(version)}").present?
    end

    def formatted_version(version)
      text = version.to_s
      return text unless text.match?(/\A\d{14}\z/)

      "#{text[0, 4]}_#{text[4, 2]}_#{text[6, 2]}_#{text[8, 6]}"
    end

    def migration_path(version)
      migrations_directory.join("#{version}_transfer_fat_tables_run_#{run.id}.rb")
    end

    def migrations_directory
      root.join("db/migrate")
    end

    def schema_path
      root.join("db/schema.rb")
    end
  end
end
