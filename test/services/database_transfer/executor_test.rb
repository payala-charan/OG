# frozen_string_literal: true

require "test_helper"

# A second connection to the test database stands in for FAT, and a scratch
# schema stands in for OG public. Transactional tests are off so the executor's
# own snapshot, transaction and rollback behave as they do for real.
class DatabaseTransferTestSourceRecord < ActiveRecord::Base
  self.abstract_class = true
end

class DatabaseTransferExecutorTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  TARGET_SCHEMA = "dbt_target_test"
  TEAMS = "dbt_src_teams"
  MEMBERS = "dbt_src_members"

  setup do
    DatabaseTransfer::ModelCatalog.reset!
    DatabaseTransferTestSourceRecord.establish_connection(ActiveRecord::Base.connection_db_config)
    @source_conn = DatabaseTransferTestSourceRecord.connection
    drop_fixtures
    create_source_tables
    ActiveRecord::Base.connection.execute("CREATE SCHEMA #{TARGET_SCHEMA}")
    @source = DatabaseTransfer::Source.new(record_class: DatabaseTransferTestSourceRecord)
    @target = DatabaseTransfer::Target.new(schema: TARGET_SCHEMA)
  end

  teardown do
    DatabaseTransfer::ModelCatalog.reset!
    drop_fixtures
    DatabaseTransferRun.delete_all
    DatabaseTransferTestSourceRecord.remove_connection
  end

  test "copies the selection and its required parent with keys, indexes and sequences" do
    run = build_run([ MEMBERS ])

    assert executor(run).call, run.reload.error_message
    run.reload

    assert run.succeeded?
    assert_not run.rehearsal?
    assert_equal [ TEAMS, MEMBERS ], run.planned_tables
    assert_equal({ TEAMS => 2, MEMBERS => 3 }, run.table_summaries.to_h { |table| [ table["name"], table["og_rows"] ] })

    assert_equal 2, target_value("SELECT COUNT(*) FROM #{target(TEAMS)}").to_i
    assert_equal 3, target_value("SELECT COUNT(*) FROM #{target(MEMBERS)}").to_i

    # COPY keeps awkward values exactly.
    assert_equal "tab\there\nnew line \\ backslash", target_value("SELECT notes FROM #{target(MEMBERS)} WHERE id = 1")
    assert_equal({ "tier" => "gold", "tags" => [ "a", "b" ] }, JSON.parse(target_value("SELECT profile FROM #{target(MEMBERS)} WHERE id = 1")))
    assert_nil target_value("SELECT notes FROM #{target(MEMBERS)} WHERE id = 3")

    constraints = target_values(<<~SQL)
      SELECT conname FROM pg_constraint con
      INNER JOIN pg_namespace n ON n.oid = con.connamespace
      WHERE n.nspname = '#{TARGET_SCHEMA}' ORDER BY conname
    SQL
    assert_includes constraints, "dbt_src_members_pkey"
    assert_includes constraints, "fk_members_team"
    assert_includes constraints, "fk_members_manager"
    assert_includes constraints, "members_email_present"

    indexes = target_values("SELECT indexname FROM pg_indexes WHERE schemaname = '#{TARGET_SCHEMA}'")
    assert_includes indexes, "index_dbt_src_members_on_lower_email"
    assert_includes indexes, "index_dbt_src_teams_on_name"

    # FAT's sequence had already reached 5 (a row was deleted), so OG continues after it.
    assert_equal 6, target_value("SELECT nextval('#{TARGET_SCHEMA}.dbt_src_members_id_seq')").to_i
    assert_equal 3, target_value("SELECT nextval('#{TARGET_SCHEMA}.dbt_src_teams_id_seq')").to_i

    # The foreign keys work in OG.
    error = assert_raises(ActiveRecord::InvalidForeignKey) do
      ActiveRecord::Base.connection.execute("INSERT INTO #{target(MEMBERS)} (team_id, email) VALUES (999, 'x@example.com')")
    end
    assert_match "fk_members_team", error.message
  end

  test "a rehearsal verifies everything and keeps nothing" do
    run = build_run([ MEMBERS ], rehearsal: true)

    assert executor(run).call, run.reload.error_message
    run.reload

    assert run.succeeded?
    assert run.summary["rolled_back"]
    assert_equal 3, run.table_summaries.find { |table| table["name"] == MEMBERS }["og_rows"]
    assert_empty target_tables
  end

  test "stops when the FAT schema changed after the plan was reviewed" do
    run = build_run([ MEMBERS ])
    @source_conn.execute("ALTER TABLE #{TEAMS} ADD COLUMN region varchar")

    assert_not executor(run).call
    run.reload

    assert run.failed?
    assert_match "changed after the plan was reviewed", run.error_message
    assert_empty target_tables
  end

  test "never touches a table that already exists in OG" do
    run = build_run([ TEAMS ])
    ActiveRecord::Base.connection.execute("CREATE TABLE #{target(TEAMS)} (id bigint, keep_me text)")
    ActiveRecord::Base.connection.execute("INSERT INTO #{target(TEAMS)} VALUES (1, 'og data')")

    assert_not executor(run).call
    run.reload

    assert run.failed?
    assert_match "#{TEAMS} already exists", run.error_message
    assert_equal [ TEAMS ], target_tables
    assert_equal "og data", target_value("SELECT keep_me FROM #{target(TEAMS)}")
    assert_equal 1, target_value("SELECT COUNT(*) FROM #{target(TEAMS)}").to_i
  end

  test "an error part way through rolls back every table" do
    run = build_run([ MEMBERS ])
    failing_source = FailingCopySource.new(record_class: DatabaseTransferTestSourceRecord, fail_on: MEMBERS)

    assert_not DatabaseTransfer::Executor.new(run, source: failing_source, target: @target).call
    run.reload

    assert run.failed?
    assert_match "copy interrupted", run.error_message
    assert_match "Nothing was written", run.progress_message
    assert_empty target_tables
  end

  test "never writes to the source" do
    run = build_run([ MEMBERS ])
    before = source_snapshot

    assert executor(run).call, run.reload.error_message
    assert_equal before, source_snapshot
  end

  test "rollback drops a committed transfer and its sequences" do
    run = build_run([ MEMBERS ])
    assert executor(run).call, run.reload.error_message
    assert Object.const_defined?(:DbtSrcTeam, false)
    assert Object.const_defined?(:DbtSrcMember, false)

    assert DatabaseTransfer::Rollback.new(run.reload, target: @target).call
    run.reload

    assert run.rolled_back?
    assert_match "Dropped 2 table(s)", run.progress_message
    assert run.summary["user_rolled_back"]
    assert_empty target_tables
    assert_empty target_values("SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = '#{TARGET_SCHEMA}'")
    refute Object.const_defined?(:DbtSrcTeam, false)
    refute Object.const_defined?(:DbtSrcMember, false)
  end

  test "rollback refuses when another target table references the transfer" do
    run = build_run([ TEAMS ])
    assert executor(run).call, run.reload.error_message
    ActiveRecord::Base.connection.execute(<<~SQL)
      CREATE TABLE #{target("dbt_extra_children")} (
        id bigint PRIMARY KEY,
        team_id bigint NOT NULL REFERENCES #{target(TEAMS)} (id)
      )
    SQL

    error = assert_raises(DatabaseTransfer::Rollback::Blocked) do
      DatabaseTransfer::Rollback.new(run.reload, target: @target).call
    end

    assert_match "dbt_extra_children", error.message
    assert run.reload.succeeded?
    assert_includes target_tables, TEAMS
  end

  test "rollback refuses a transfer that a later committed run also includes" do
    run = build_run([ TEAMS ])
    assert executor(run).call, run.reload.error_message
    later = DatabaseTransferRun.create!(
      source_database: run.source_database,
      target_database: run.target_database,
      plan_fingerprint: "later",
      status: :succeeded,
      selected_tables: [ TEAMS ],
      planned_tables: [ TEAMS ]
    )

    error = assert_raises(DatabaseTransfer::Rollback::Blocked) do
      DatabaseTransfer::Rollback.new(run.reload, target: @target).call
    end

    assert_match "##{later.id}", error.message
    assert_includes target_tables, TEAMS

    assert DatabaseTransfer::Rollback.new(later, target: @target).call
    assert later.reload.rolled_back?
    assert_empty target_tables
  end

  test "rollback refuses a rehearsal" do
    run = build_run([ MEMBERS ], rehearsal: true)
    assert executor(run).call, run.reload.error_message

    error = assert_raises(DatabaseTransfer::Rollback::Blocked) do
      DatabaseTransfer::Rollback.new(run.reload, target: @target).call
    end

    assert_match "rehearsal", error.message
    assert_empty target_tables
  end

  test "runs a claimed run only once" do
    run = build_run([ MEMBERS ])

    assert executor(run).call
    assert_not executor(run).call
    assert run.reload.succeeded?
  end

  test "only one transfer can hold the lock at a time" do
    run = build_run([ MEMBERS ])
    holder = ActiveRecord::Base.connection_pool.checkout
    begin
      holder.execute("BEGIN")
      holder.execute("SELECT pg_advisory_xact_lock(#{DatabaseTransfer::Target::LOCK_KEY})")

      assert_not executor(run).call
      assert_match "Another database transfer is running", run.reload.error_message
    ensure
      holder.execute("ROLLBACK")
      ActiveRecord::Base.connection_pool.checkin(holder)
    end
    assert_empty target_tables
  end

  private

  def executor(run)
    DatabaseTransfer::Executor.new(run, source: @source, target: @target)
  end

  def build_run(tables, rehearsal: false)
    known = DatabaseTransfer::TableDiscovery.new(source: @source).table_names
    analysis = DatabaseTransfer::DependencyResolver.new(source: @source).resolve(tables, known_tables: known)
    plan = DatabaseTransfer::Planner.new(source: @source, target: @target).build(analysis)
    assert plan.transferable?, (plan.blockers + plan.blocked_tables.flat_map(&:blockers)).join(" ")

    DatabaseTransferRun.create!(
      rehearsal: rehearsal,
      source_database: plan.source_database,
      target_database: plan.target_database,
      selected_tables: plan.selected_tables,
      planned_tables: plan.table_names,
      plan_fingerprint: plan.fingerprint
    )
  end

  def create_source_tables
    @source_conn.execute(<<~SQL)
      CREATE TABLE #{TEAMS} (
        id bigserial PRIMARY KEY,
        name varchar NOT NULL DEFAULT '',
        created_at timestamp(6) NOT NULL DEFAULT now()
      );
      CREATE UNIQUE INDEX index_dbt_src_teams_on_name ON #{TEAMS} (name);
      INSERT INTO #{TEAMS} (name) VALUES ('Alpha'), ('Beta');

      CREATE TABLE #{MEMBERS} (
        id bigserial PRIMARY KEY,
        team_id bigint NOT NULL,
        manager_id bigint,
        email varchar,
        notes text,
        profile jsonb DEFAULT '{}'::jsonb,
        score numeric(10,2),
        CONSTRAINT members_email_present CHECK (email IS NULL OR email <> ''),
        CONSTRAINT fk_members_team FOREIGN KEY (team_id) REFERENCES #{TEAMS}(id),
        CONSTRAINT fk_members_manager FOREIGN KEY (manager_id) REFERENCES #{MEMBERS}(id) ON DELETE SET NULL
      );
      CREATE INDEX index_dbt_src_members_on_lower_email ON #{MEMBERS} (lower(email)) WHERE email IS NOT NULL;
      INSERT INTO #{MEMBERS} (team_id, manager_id, email, notes, profile, score) VALUES
        (1, NULL, 'a@example.com', E'tab\\there\\nnew line \\\\ backslash', '{"tier":"gold","tags":["a","b"]}', 12.50),
        (1, 1, 'b@example.com', 'plain', '{}', NULL),
        (2, 1, NULL, NULL, NULL, 3.10),
        (2, NULL, 'gone@example.com', 'deleted later', '{}', 0);
      SELECT setval('dbt_src_members_id_seq', 5);
      DELETE FROM #{MEMBERS} WHERE email = 'gone@example.com';
    SQL
  end

  def drop_fixtures
    @source_conn&.execute("DROP TABLE IF EXISTS #{MEMBERS}, #{TEAMS} CASCADE")
    ActiveRecord::Base.connection.execute("DROP SCHEMA IF EXISTS #{TARGET_SCHEMA} CASCADE")
  end

  def target(name)
    %("#{TARGET_SCHEMA}"."#{name}")
  end

  def target_value(sql)
    ActiveRecord::Base.connection.select_value(sql)
  end

  def target_values(sql)
    ActiveRecord::Base.connection.select_values(sql)
  end

  def target_tables
    target_values("SELECT tablename FROM pg_tables WHERE schemaname = '#{TARGET_SCHEMA}' ORDER BY tablename")
  end

  def source_snapshot
    [
      @source_conn.select_rows("SELECT * FROM #{TEAMS} ORDER BY id"),
      @source_conn.select_rows("SELECT * FROM #{MEMBERS} ORDER BY id"),
      @source_conn.select_value("SELECT last_value FROM dbt_src_members_id_seq")
    ]
  end

  class FailingCopySource < DatabaseTransfer::Source
    def initialize(fail_on:, **options)
      super(**options)
      @fail_on = fail_on
    end

    def copy_rows(table_name, column_names, &block)
      raise "copy interrupted" if table_name == @fail_on

      super
    end
  end
end
