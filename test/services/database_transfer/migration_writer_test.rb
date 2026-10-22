# frozen_string_literal: true

require "test_helper"

class DatabaseTransferMigrationWriterTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  PARENT = "dbt_mig_parents"
  CHILD = "dbt_mig_children"

  setup do
    @root = Pathname(Dir.mktmpdir("dbt-migration"))
    FileUtils.mkdir_p(@root.join("db/migrate"))
    @root.join("db/schema.rb").write(<<~RUBY)
      ActiveRecord::Schema[8.0].define(version: 2026_09_28_090000) do
        create_table "excel_records", force: :cascade do |t|
          t.string "name"
        end

        create_table "github_accounts", force: :cascade do |t|
          t.string "username"
        end

        add_foreign_key "github_accounts", "users"
      end
    RUBY
    connection.execute("DROP TABLE IF EXISTS #{CHILD}, #{PARENT} CASCADE")
    connection.execute("CREATE TABLE #{PARENT} (id bigserial PRIMARY KEY, name varchar NOT NULL)")
    connection.execute(<<~SQL)
      CREATE TABLE #{CHILD} (
        id bigserial PRIMARY KEY,
        dbt_mig_parent_id bigint NOT NULL,
        CONSTRAINT fk_dbt_mig_child FOREIGN KEY (dbt_mig_parent_id) REFERENCES #{PARENT} (id)
      )
    SQL
    @run = DatabaseTransferRun.create!(
      source_database: "fat",
      target_database: connection_db_config_name,
      plan_fingerprint: "migration",
      status: :succeeded,
      rehearsal: false,
      selected_tables: [ CHILD ],
      planned_tables: [ PARENT, CHILD ],
      summary: { "tables" => [] }
    )
  end

  teardown do
    version = @run.reload.summary["migration_version"]
    if version.present?
      connection.execute("DELETE FROM schema_migrations WHERE version = #{connection.quote(version)}")
    end
    connection.execute("DROP TABLE IF EXISTS #{CHILD}, #{PARENT} CASCADE")
    DatabaseTransferRun.delete_all
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  test "writes a migration and schema entries for the foreign key" do
    version = DatabaseTransfer::MigrationWriter.record!(@run, root: @root)

    assert version.present?
    source = @root.join("db/migrate/#{version}_transfer_fat_tables_run_#{@run.id}.rb").read
    assert_includes source, "create_table :#{PARENT}"
    assert_includes source, "create_table :#{CHILD}"
    assert_includes source, "add_foreign_key :#{CHILD}, :#{PARENT}"
    assert_operator source.index("create_table :#{PARENT}"), :<, source.index("create_table :#{CHILD}")

    schema = @root.join("db/schema.rb").read
    assert_includes schema, "create_table \"#{PARENT}\""
    assert_includes schema, "create_table \"#{CHILD}\""
    assert_includes schema, "add_foreign_key \"#{CHILD}\", \"#{PARENT}\""
    assert_includes schema, "version: #{version[0, 4]}_#{version[4, 2]}_#{version[6, 2]}_#{version[8, 6]}"
    assert_includes connection.select_values("SELECT version FROM schema_migrations"), version

    DatabaseTransfer::MigrationWriter.revert!(@run.reload, root: @root)

    refute @root.join("db/migrate/#{version}_transfer_fat_tables_run_#{@run.id}.rb").exist?
    schema = @root.join("db/schema.rb").read
    refute_includes schema, "create_table \"#{PARENT}\""
    refute_includes schema, "add_foreign_key \"#{CHILD}\""
    refute_includes connection.select_values("SELECT version FROM schema_migrations"), version
    assert_nil @run.reload.summary["migration_version"]
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def connection_db_config_name
    ActiveRecord::Base.connection_db_config.database
  end
end
