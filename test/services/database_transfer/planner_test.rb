# frozen_string_literal: true

require "test_helper"

class DatabaseTransferPlannerTest < ActiveSupport::TestCase
  test "plans selected tables and required parents in load order" do
    plan = build_plan

    assert plan.transferable?
    assert_equal [ "teams", "members" ], plan.table_names
    assert_equal [ :required, :selected ], plan.tables.map(&:role)
    assert_equal 5, plan.total_rows
    assert_equal "og_db", plan.target_database
  end

  test "blocks a table that already exists in OG" do
    plan = build_plan(existing: [ "teams" ])

    assert_not plan.transferable?
    assert_match "teams already exists in og_db", plan.tables.first.blockers.first
    assert_not plan.tables.last.blocked?
  end

  test "blocks when an index or sequence name is already taken in OG" do
    plan = build_plan(existing: [ "members_id_seq" ])

    assert_not plan.transferable?
    assert_match "og_db already has objects named members_id_seq", plan.tables.last.blockers.first
  end

  test "never transfers Rails bookkeeping tables" do
    plan = build_plan(order: [ "schema_migrations" ], selected: [ "schema_migrations" ])

    assert_not plan.transferable?
    assert_match "Rails bookkeeping", plan.tables.first.blockers.first
  end

  test "blocks definitions the transfer cannot reproduce" do
    definitions = default_definitions
    definitions["members"].unsupported << "column id is an identity column"
    plan = build_plan(definitions: definitions)

    assert_not plan.transferable?
    assert_includes plan.tables.last.blockers, "members column id is an identity column."
  end

  test "blocks a foreign key to a table outside the plan" do
    definitions = default_definitions
    definitions["members"].foreign_keys << constraint("fk_owner", "f", "FOREIGN KEY (owner_id) REFERENCES users(id)", "users")
    plan = build_plan(definitions: definitions)

    assert_not plan.transferable?
    assert_match "fk_owner points at public.users", plan.tables.last.blockers.first
  end

  test "blocks a table that disappeared from FAT" do
    definitions = default_definitions.except("teams")
    plan = build_plan(definitions: definitions)

    assert_not plan.transferable?
    assert_match "no longer a table", plan.tables.first.blockers.first
  end

  test "mentions referencing tables that are left out" do
    plan = build_plan(referencing: [ "notes" ])

    assert_match "1 related table(s) are not included: notes", plan.warnings.first
  end

  test "fingerprint changes with the FAT definition, not with row counts" do
    first = build_plan.fingerprint

    assert_equal first, build_plan(counts: { "teams" => 99 }).fingerprint

    definitions = default_definitions
    definitions["teams"].columns << column("region", "character varying")
    assert_not_equal first, build_plan(definitions: definitions).fingerprint
  end

  private

  def build_plan(order: [ "teams", "members" ], selected: [ "members" ], existing: [], referencing: [],
                 definitions: default_definitions, counts: { "teams" => 2, "members" => 3 })
    analysis = DatabaseTransfer::Analysis.new(
      selected_tables: selected,
      required_tables: (order - selected).map do |name|
        DatabaseTransfer::TableDependency.new(name: name, reasons: [], chain: [ name ], direction: :required)
      end,
      referencing_tables: referencing.map do |name|
        DatabaseTransfer::TableDependency.new(name: name, reasons: [], chain: [ name ], direction: :referencing)
      end,
      external_dependencies: [],
      dependency_order: order,
      cyclic: false,
      ignored_tables: [],
      outgoing_edges: {},
      incoming_edges: {}
    )
    source = FakeDatabaseTransferSource.new(database: "fat_db")
    catalog = FakeCatalog.new("og_db", existing)
    target = DatabaseTransfer::Target.new
    reader = FakeSchemaReader.new(definitions)

    DatabaseTransfer::Planner.new(source: source, target: target, schema_reader: reader)
                             .build(analysis, counts: counts, catalog: catalog)
  end

  def default_definitions
    {
      "teams" => definition("teams", sequences: [ sequence("teams_id_seq") ]),
      "members" => definition(
        "members",
        sequences: [ sequence("members_id_seq") ],
        foreign_keys: [ constraint("fk_team", "f", "FOREIGN KEY (team_id) REFERENCES teams(id)", "teams") ]
      ),
      "schema_migrations" => definition("schema_migrations")
    }
  end

  def definition(name, sequences: [], foreign_keys: [])
    DatabaseTransfer::TableDefinition.new(
      name: name,
      columns: [ column("id", "bigint") ],
      constraints: [ constraint("#{name}_pkey", "p", "PRIMARY KEY (id)") ],
      foreign_keys: foreign_keys,
      indexes: [],
      sequences: sequences,
      unsupported: [],
      warnings: []
    )
  end

  def column(name, type)
    DatabaseTransfer::ColumnDefinition.new(name: name, data_type: type, not_null: false, default_sql: nil)
  end

  def constraint(name, kind, definition, target_table = nil)
    DatabaseTransfer::ConstraintDefinition.new(
      name: name, kind: kind, definition: definition,
      target_schema: target_table && "public", target_table: target_table
    )
  end

  def sequence(name)
    DatabaseTransfer::SequenceDefinition.new(
      name: name, column_name: "id", data_type: "bigint", start_value: 1, increment_by: 1,
      min_value: 1, max_value: 9_223_372_036_854_775_807, cache_size: 1, cycle: false
    )
  end

  FakeCatalog = Struct.new(:database_name, :names) do
    def existing_names(candidates)
      candidates.select { |name| names.include?(name) }.to_set
    end
  end

  class FakeSchemaReader
    def initialize(definitions)
      @definitions = definitions
    end

    def read(names)
      @definitions.slice(*names)
    end
  end
end
