# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class DatabaseTransfersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(
      email: "db-transfer-#{SecureRandom.hex(6)}@example.com",
      password: "password123"
    )
  end

  test "requires login" do
    get database_transfers_path

    assert_redirected_to login_path
  end

  test "shows the source database, counts, and analyze action" do
    log_in
    with_catalog do
      get database_transfers_path
    end

    assert_response :success
    assert_select "#source-database", "updated_db"
    assert_select "label", "sftp_portal_logins"
    assert_match "12", response.body
    assert_select "button", text: /Analyze Dependencies/
    assert_select "button", text: /Start transfer|Copy data/, count: 0
  end

  test "analyze renders required parents and referencing tables" do
    log_in
    with_catalog do |resolver|
      post analyze_database_transfers_path, params: { tables: [ "sftp_portal_logins", "not_a_table" ] }
      assert_equal [ "sftp_portal_logins" ], resolver.names
    end

    assert_response :success
    assert_match "Automatically Required", response.body
    assert_match "sftp_portal_logins.team_id → teams.id", response.body
    assert_match "References selection", response.body
    assert_match "sftp_portal_users.sftp_portal_user_id → sftp_portal_logins.id", response.body
    assert_select "input[name='include_related[]'][value='sftp_portal_users']"
    assert_select "input[name='include_related[]'][value='sftp_portal_users'][checked]", count: 0
    assert_select "button", text: /Update plan/
    assert_match "Ignored names that are not tables in updated_db: not_a_table.", response.body
    assert_select "input[checked][value=?]", "sftp_portal_logins"
    assert_select "#transfer-plan"
    assert_select "button", text: /Rehearse transfer/
    assert_select "button", text: /Start transfer/
  end

  test "including a related table plans that table with the selection" do
    log_in
    with_catalog do |resolver|
      post analyze_database_transfers_path, params: {
        tables: [ "sftp_portal_logins" ],
        include_related: [ "sftp_portal_users", "not_related" ]
      }
      assert_equal [ [ "sftp_portal_logins" ], [ "sftp_portal_logins", "sftp_portal_users" ] ], resolver.calls
    end

    assert_response :success
    assert_select "input[name='include_related[]'][value='sftp_portal_users'][checked]"
    assert_select "input[type=hidden][name='include_related[]'][value='sftp_portal_users']"
    assert_match "Ignored related tables that do not reference this selection: not_related.", response.body
    assert_match "Included related table", response.body
  end

  test "a blocked plan explains why and offers no transfer" do
    log_in
    with_catalog(blocked: true) do
      post analyze_database_transfers_path, params: { tables: [ "sftp_portal_logins" ] }
    end

    assert_response :success
    assert_match "teams already exists in excel_development", response.body
    assert_select "button", text: /Start transfer/, count: 0
  end

  test "transfer requires typing the target database name" do
    log_in
    assert_no_difference -> { DatabaseTransferRun.count } do
      with_catalog do
        post transfer_database_transfers_path,
             params: { tables: [ "sftp_portal_logins" ], plan_fingerprint: "abc123", confirm_database: "excel" }
      end
    end

    assert_response :unprocessable_entity
    assert_match "Type excel_development exactly to confirm the transfer.", response.body
  end

  test "transfer refuses a plan that changed since it was reviewed" do
    log_in
    assert_no_difference -> { DatabaseTransferRun.count } do
      with_catalog do
        post transfer_database_transfers_path,
             params: { tables: [ "sftp_portal_logins" ], plan_fingerprint: "stale", confirm_database: "excel_development" }
      end
    end

    assert_response :unprocessable_entity
    assert_match "changed since you reviewed the plan", response.body
  end

  test "transfer refuses a blocked plan" do
    log_in
    assert_no_difference -> { DatabaseTransferRun.count } do
      with_catalog(blocked: true) do
        post transfer_database_transfers_path,
             params: { tables: [ "sftp_portal_logins" ], plan_fingerprint: "abc123", confirm_database: "excel_development" }
      end
    end

    assert_response :unprocessable_entity
    assert_match "This plan is blocked", response.body
  end

  test "transfer refuses while another run is active" do
    log_in
    DatabaseTransferRun.create!(source_database: "updated_db", target_database: "excel_development",
                                plan_fingerprint: "old", status: :running)
    assert_no_difference -> { DatabaseTransferRun.count } do
      with_catalog do
        post transfer_database_transfers_path,
             params: { tables: [ "sftp_portal_logins" ], plan_fingerprint: "abc123", confirm_database: "excel_development" }
      end
    end

    assert_response :unprocessable_entity
    assert_match "Another transfer is already waiting or running", response.body
  end

  test "transfer records a run from the server-side plan and shows its progress" do
    log_in
    with_catalog do |resolver|
      post transfer_database_transfers_path,
           params: {
             tables: [ "sftp_portal_logins" ],
             plan_fingerprint: "abc123",
             confirm_database: " excel_development "
           }
      assert_equal [ "sftp_portal_logins" ], resolver.names
    end

    run = DatabaseTransferRun.last
    assert_redirected_to database_transfer_run_path(run)
    assert run.pending?
    assert_not run.rehearsal?
    assert_equal @user, run.user
    assert_equal [ "sftp_portal_logins" ], run.selected_tables
    assert_equal [ "teams", "sftp_portal_logins" ], run.planned_tables
    assert_equal "abc123", run.plan_fingerprint
    assert_equal "updated_db", run.source_database
    assert_equal "excel_development", run.target_database

    follow_redirect!
    assert_response :success
    assert_select "#run-status", /Pending/
    assert_select "td strong", text: "teams"
  end

  test "a rehearsal does not need the confirmation text" do
    log_in
    with_catalog do
      post transfer_database_transfers_path,
           params: { tables: [ "sftp_portal_logins" ], plan_fingerprint: "abc123", rehearsal: "1" }
    end

    run = DatabaseTransferRun.last
    assert_redirected_to database_transfer_run_path(run)
    assert run.rehearsal?
  end

  test "lists transfer history" do
    log_in
    DatabaseTransferRun.create!(source_database: "updated_db", target_database: "excel_development",
                                plan_fingerprint: "done", status: :failed, error_message: "boom",
                                planned_tables: [ "teams" ])

    get database_transfer_runs_path

    assert_response :success
    assert_select "td", text: "Failed"
    assert_select "a", text: "Roll back", count: 0
  end

  test "a committed run shows the console model and a rollback form" do
    log_in
    run = committed_run

    get database_transfer_run_path(run)

    assert_response :success
    assert_match "AccountingPeriod.all", response.body
    assert_select "form[action=?]", rollback_database_transfer_run_path(run)
    assert_select "button", text: /Roll back tables/
  end

  test "a rehearsal does not offer rollback" do
    log_in
    run = committed_run(rehearsal: true)

    get database_transfer_run_path(run)

    assert_response :success
    assert_select "form[action=?]", rollback_database_transfer_run_path(run), count: 0
    assert_no_match "AccountingPeriod.all", response.body
  end

  test "recent transfers link a committed run to rollback" do
    log_in
    run = committed_run
    with_catalog do
      get database_transfers_path
    end

    assert_response :success
    assert_select "a.dbt-rollback[href=?]", "#{database_transfer_run_path(run)}#rollback"
  end

  test "rollback requires the target database name" do
    log_in
    run = committed_run

    post rollback_database_transfer_run_path(run), params: { confirm_database: "excel" }

    assert_redirected_to database_transfer_run_path(run, anchor: "rollback")
    assert run.reload.succeeded?
    follow_redirect!
    assert_match "Type excel_development exactly to roll back these tables.", response.body
  end

  test "rollback reports a blocked drop" do
    log_in
    run = committed_run
    service = Object.new
    service.define_singleton_method(:call) do
      raise DatabaseTransfer::Rollback::Blocked, "Other tables still reference this transfer: child_rows."
    end

    DatabaseTransfer::Rollback.stub(:new, ->(record) { service }) do
      post rollback_database_transfer_run_path(run), params: { confirm_database: "excel_development" }
    end

    assert_redirected_to database_transfer_run_path(run)
    assert run.reload.succeeded?
    follow_redirect!
    assert_match "child_rows", response.body
  end

  test "rollback redirects when the drop is confirmed" do
    log_in
    run = committed_run
    service = Minitest::Mock.new
    service.expect(:call, true)

    DatabaseTransfer::Rollback.stub(:new, ->(record) {
      assert_equal run.id, record.id
      service
    }) do
      post rollback_database_transfer_run_path(run), params: { confirm_database: " excel_development " }
    end

    assert_mock service
    assert_redirected_to database_transfer_run_path(run)
    follow_redirect!
    assert_match "Rolled back 1 table(s). They were dropped from excel_development.", response.body
  end

  test "asks for a selection before analyzing" do
    log_in
    with_catalog do
      post analyze_database_transfers_path
    end

    assert_response :unprocessable_entity
    assert_match "Select at least one table before analyzing dependencies.", response.body
  end

  test "refreshes counts and returns to the dashboard" do
    log_in
    with_catalog do
      get database_transfers_path(refresh: 1)
    end

    assert_redirected_to database_transfers_path
  end

  private

  def log_in
    post login_path, params: { email: @user.email, password: "password123" }
  end

  def committed_run(rehearsal: false)
    DatabaseTransferRun.create!(
      source_database: "updated_db",
      target_database: "excel_development",
      plan_fingerprint: "done",
      status: :succeeded,
      rehearsal: rehearsal,
      selected_tables: [ "accounting_periods" ],
      planned_tables: [ "accounting_periods" ]
    )
  end

  def with_catalog(blocked: false)
    discovery = Object.new
    discovery.define_singleton_method(:source_database) { "updated_db" }
    discovery.define_singleton_method(:tables_with_counts) do |refresh: false|
      [
        { name: "sftp_portal_logins", count: 12 },
        { name: "sftp_portal_users", count: 3 }
      ]
    end

    edge = DatabaseTransfer::Edge.new(
      from_table: "sftp_portal_users",
      from_column: "sftp_portal_user_id",
      to_schema: "public",
      to_table: "sftp_portal_logins",
      to_column: "id",
      constraint_name: "fk_users"
    )
    required_edge = DatabaseTransfer::Edge.new(
      from_table: "sftp_portal_logins",
      from_column: "team_id",
      to_schema: "public",
      to_table: "teams",
      to_column: "id",
      constraint_name: "fk_team"
    )
    analysis = DatabaseTransfer::Analysis.new(
      selected_tables: [ "sftp_portal_logins" ],
      required_tables: [
        DatabaseTransfer::TableDependency.new(
          name: "teams",
          reasons: [ required_edge ],
          chain: [ "sftp_portal_logins", "teams" ],
          direction: :required
        )
      ],
      referencing_tables: [
        DatabaseTransfer::TableDependency.new(
          name: "sftp_portal_users",
          reasons: [ edge ],
          chain: [ "sftp_portal_logins", "sftp_portal_users" ],
          direction: :referencing
        )
      ],
      external_dependencies: [],
      dependency_order: [ "sftp_portal_logins", "sftp_portal_users" ],
      cyclic: false,
      ignored_tables: [],
      outgoing_edges: {},
      incoming_edges: { "sftp_portal_logins" => [ edge ] }
    )
    resolver = CapturingResolver.new(analysis)
    planner = StaticPlanner.new(build_plan(blocked: blocked))

    DatabaseTransfer::TableDiscovery.stub(:new, discovery) do
      DatabaseTransfer::DependencyResolver.stub(:new, resolver) do
        DatabaseTransfer::Planner.stub(:new, planner) do
          yield resolver
        end
      end
    end
  end

  def build_plan(blocked:)
    tables = [
      DatabaseTransfer::Plan::PlannedTable.new(
        name: "teams", role: :required, definition: nil, row_count: 4,
        blockers: blocked ? [ "teams already exists in excel_development." ] : [], warnings: []
      ),
      DatabaseTransfer::Plan::PlannedTable.new(
        name: "sftp_portal_logins", role: :selected, definition: nil, row_count: 12, blockers: [], warnings: []
      )
    ]
    DatabaseTransfer::Plan.new(
      source_database: "updated_db",
      target_database: "excel_development",
      selected_tables: [ "sftp_portal_logins" ],
      tables: tables,
      blockers: [],
      warnings: [],
      fingerprint: "abc123"
    )
  end
end

class CapturingResolver
  attr_reader :names

  def initialize(analysis)
    @analysis = analysis
  end

  def resolve(names, known_tables:)
    @calls ||= []
    @calls << names
    @names = names
    @known_tables = known_tables
    @analysis
  end

  def calls
    Array(@calls)
  end
end

class StaticPlanner
  def initialize(plan)
    @plan = plan
  end

  def build(_analysis, counts: {})
    @plan
  end
end
