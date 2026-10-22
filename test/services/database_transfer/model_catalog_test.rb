# frozen_string_literal: true

require "test_helper"

class DatabaseTransferModelCatalogTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  TABLE = "dbt_catalog_widgets"

  setup do
    DatabaseTransfer::ModelCatalog.reset!
    connection.execute("DROP TABLE IF EXISTS #{TABLE}")
    connection.execute(<<~SQL)
      CREATE TABLE #{TABLE} (
        id bigserial PRIMARY KEY,
        name varchar NOT NULL
      )
    SQL
    connection.execute("INSERT INTO #{TABLE} (name) VALUES ('alpha')")
    @run = committed_run(planned_tables: [ TABLE ], selected_tables: [ TABLE ])
  end

  teardown do
    DatabaseTransfer::ModelCatalog.reset!
    connection.execute("DROP TABLE IF EXISTS #{TABLE}")
    DatabaseTransferRun.delete_all
  end

  test "names a table the way the console expects" do
    assert_equal "AccountingPeriod", DatabaseTransfer::ModelCatalog.constant_name_for("accounting_periods")
  end

  test "defines a model that reads the transferred table" do
    assert DatabaseTransfer::ModelCatalog.sync!

    assert Object.const_defined?(:DbtCatalogWidget, false)
    assert_same DbtCatalogWidget, DatabaseTransfer::Models::DbtCatalogWidget
    assert_equal [ "alpha" ], DbtCatalogWidget.order(:id).pluck(:name)
    assert DbtCatalogWidget.database_transfer_model?
    assert_predicate DbtCatalogWidget.inheritance_column, :blank?
  end

  test "removes the model when the transfer is rolled back" do
    DatabaseTransfer::ModelCatalog.sync!
    assert Object.const_defined?(:DbtCatalogWidget, false)

    @run.update!(status: :rolled_back)
    DatabaseTransfer::ModelCatalog.sync!

    refute Object.const_defined?(:DbtCatalogWidget, false)
  end

  test "ignores a rehearsal" do
    @run.update!(rehearsal: true)

    DatabaseTransfer::ModelCatalog.sync!

    refute Object.const_defined?(:DbtCatalogWidget, false)
  end

  test "does not replace an application model" do
    original = User
    reflections = User.reflections.keys
    committed_run(planned_tables: [ "users" ], selected_tables: [ "users" ], plan_fingerprint: "users")

    DatabaseTransfer::ModelCatalog.sync!

    assert_same original, User
    assert_equal reflections, User.reflections.keys
    refute_respond_to User, :database_transfer_model?
    assert DatabaseTransfer::Models::User.database_transfer_model?
    refute_same User, DatabaseTransfer::Models::User
    assert_equal "DatabaseTransfer::Models::User", DatabaseTransfer::ModelCatalog.console_constant("users")
  end

  test "links transferred tables through their foreign keys" do
    connection.execute("DROP TABLE IF EXISTS dbt_catalog_children, dbt_catalog_parents CASCADE")
    connection.execute(<<~SQL)
      CREATE TABLE dbt_catalog_parents (
        id bigserial PRIMARY KEY
      )
    SQL
    connection.execute(<<~SQL)
      CREATE TABLE dbt_catalog_children (
        id bigserial PRIMARY KEY,
        dbt_catalog_parent_id bigint REFERENCES dbt_catalog_parents (id)
      )
    SQL
    connection.execute(<<~SQL)
      CREATE UNIQUE INDEX index_dbt_catalog_children_on_parent
      ON dbt_catalog_children (dbt_catalog_parent_id)
    SQL
    committed_run(
      planned_tables: [ "dbt_catalog_parents", "dbt_catalog_children" ],
      selected_tables: [ "dbt_catalog_children" ],
      plan_fingerprint: "relations"
    )

    DatabaseTransfer::ModelCatalog.sync!

    assert_equal [ "dbt_catalog_child" ], DbtCatalogParent.reflections.keys
    assert_equal [ "dbt_catalog_parent" ], DbtCatalogChild.reflections.keys
    assert_predicate DbtCatalogChild.reflect_on_association(:dbt_catalog_parent), :belongs_to?
    assert_predicate DbtCatalogParent.reflect_on_association(:dbt_catalog_child), :has_one?
    assert DbtCatalogChild.reflect_on_association(:dbt_catalog_parent).options[:optional]
  ensure
    DatabaseTransfer::ModelCatalog.reset!
    connection.execute("DROP TABLE IF EXISTS dbt_catalog_children, dbt_catalog_parents CASCADE")
  end

  private

  def connection
    ActiveRecord::Base.connection
  end

  def committed_run(planned_tables:, selected_tables:, plan_fingerprint: "catalog")
    DatabaseTransferRun.create!(
      source_database: "fat",
      target_database: ActiveRecord::Base.connection_db_config.database,
      plan_fingerprint: plan_fingerprint,
      status: :succeeded,
      rehearsal: false,
      selected_tables: selected_tables,
      planned_tables: planned_tables
    )
  end
end
