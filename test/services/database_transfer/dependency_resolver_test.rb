# frozen_string_literal: true

require "test_helper"
require_relative "../../support/fake_database_transfer_source"

class DatabaseTransferDependencyResolverTest < ActiveSupport::TestCase
  test "follows outgoing foreign keys recursively and orders parents first" do
    analysis = resolve(
      [ "sftp_portal_logins" ],
      %w[sftp_portal_logins sftp_portal_users sftp_portal_verification_codes],
      [
        fk("sftp_portal_logins", "sftp_portal_user_id", "sftp_portal_users"),
        fk("sftp_portal_logins", "sftp_portal_verification_code_id", "sftp_portal_verification_codes"),
        fk("sftp_portal_verification_codes", "sftp_portal_user_id", "sftp_portal_users")
      ]
    )

    assert_equal [ "sftp_portal_logins" ], analysis.selected_tables
    assert_equal [ "sftp_portal_users", "sftp_portal_verification_codes" ], analysis.required_tables.map(&:name)
    users = analysis.required_tables.find { |table| table.name == "sftp_portal_users" }
    assert_equal [ "sftp_portal_logins", "sftp_portal_users" ], users.chain
    assert_equal 2, users.reasons.size
    assert_includes users.reasons.map(&:summary), "sftp_portal_verification_codes.sftp_portal_user_id → sftp_portal_users.id"
    assert_equal(
      %w[sftp_portal_users sftp_portal_verification_codes sftp_portal_logins],
      analysis.dependency_order
    )
    assert_not analysis.cyclic?
  end

  test "reports tables that reference the selection without treating them as required parents" do
    analysis = resolve(
      [ "utilization_reports" ],
      %w[accounting_periods ndc_codes primary_payors test_invoice_conversions utilization_orders utilization_reports],
      [
        fk("ndc_codes", "utilization_report_id", "utilization_reports"),
        fk("primary_payors", "utilization_report_id", "utilization_reports"),
        fk("utilization_orders", "utilization_report_id", "utilization_reports"),
        fk("test_invoice_conversions", "utilization_report_id", "utilization_reports"),
        fk("client_file_checklists", "accounting_period_id", "accounting_periods")
      ]
    )

    assert_empty analysis.required_tables
    assert_equal(
      %w[ndc_codes primary_payors test_invoice_conversions utilization_orders],
      analysis.referencing_tables.map(&:name)
    )
    ndc = analysis.referencing_tables.find { |table| table.name == "ndc_codes" }
    assert_equal [ "utilization_reports", "ndc_codes" ], ndc.chain
    assert_equal "utilization_reports ← ndc_codes", ndc.chain_label
    assert_equal "ndc_codes.utilization_report_id → utilization_reports.id", ndc.reasons.first.summary
    assert_equal [ "utilization_reports" ], analysis.dependency_order
  end

  test "copies a related table and the tables it depends on when that table is selected" do
    analysis = resolve(
      [ "users", "order_set_comments" ],
      %w[order_set_comments order_sets users],
      [
        fk("order_sets", "user_id", "users"),
        fk("order_set_comments", "order_set_id", "order_sets")
      ]
    )

    assert_equal %w[order_set_comments users], analysis.selected_tables
    assert_equal [ "order_sets" ], analysis.required_tables.map(&:name)
    assert_empty analysis.referencing_tables
    assert_equal %w[users order_sets order_set_comments], analysis.dependency_order
  end

  test "walks referencing tables recursively" do
    analysis = resolve(
      [ "users" ],
      %w[order_set_comments order_sets users],
      [
        fk("order_sets", "user_id", "users"),
        fk("order_set_comments", "order_set_id", "order_sets")
      ]
    )

    comments = analysis.referencing_tables.find { |table| table.name == "order_set_comments" }
    assert_equal %w[order_set_comments order_sets], analysis.referencing_tables.map(&:name)
    assert_equal "users ← order_sets ← order_set_comments", comments.chain_label
    assert_empty analysis.required_tables
  end

  test "keeps a selected parent out of the required list" do
    analysis = resolve(
      [ "sftp_portal_logins", "sftp_portal_users" ],
      %w[sftp_portal_logins sftp_portal_users sftp_portal_verification_codes],
      [
        fk("sftp_portal_logins", "sftp_portal_user_id", "sftp_portal_users"),
        fk("sftp_portal_logins", "sftp_portal_verification_code_id", "sftp_portal_verification_codes"),
        fk("sftp_portal_verification_codes", "sftp_portal_user_id", "sftp_portal_users")
      ]
    )

    assert_equal [ "sftp_portal_verification_codes" ], analysis.required_tables.map(&:name)
    assert_equal(
      %w[sftp_portal_users sftp_portal_verification_codes sftp_portal_logins],
      analysis.dependency_order
    )
  end

  test "stops on cycles and self references" do
    cycle = resolve(
      [ "a" ],
      %w[a b],
      [ fk("a", "b_id", "b"), fk("b", "a_id", "a") ]
    )
    assert_equal [ "b" ], cycle.required_tables.map(&:name)
    assert_equal %w[a b], cycle.dependency_order
    assert cycle.cyclic?

    self_ref = resolve(
      [ "utilization_histories" ],
      %w[utilization_histories],
      [ fk("utilization_histories", "source_utilization_history_id", "utilization_histories") ]
    )
    assert_empty self_ref.required_tables
    assert_not self_ref.cyclic?
    assert self_ref.tree_for("utilization_histories").first[:self_reference]
  end

  test "orders a diamond with each parent ahead of its children" do
    analysis = resolve(
      [ "a" ],
      %w[a b c d],
      [
        fk("a", "b_id", "b"),
        fk("a", "c_id", "c"),
        fk("b", "d_id", "d"),
        fk("c", "d_id", "d")
      ]
    )

    assert_equal %w[b c d], analysis.required_tables.map(&:name)
    assert_equal %w[d b c a], analysis.dependency_order
    assert_equal [ "a", "b", "d" ], analysis.required_tables.find { |table| table.name == "d" }.chain
  end

  test "ignores unknown names and does not interpolate them into SQL" do
    source = FakeDatabaseTransferSource.new(foreign_keys: [])
    analysis = DatabaseTransfer::DependencyResolver.new(source: source).resolve(
      [ "zz_marker_table", "missing" ],
      known_tables: [ "zz_marker_table" ]
    )

    assert_equal [ "zz_marker_table" ], analysis.selected_tables
    assert_equal [ "missing" ], analysis.ignored_tables
    assert source.statements.none? { |sql| sql.include?("zz_marker_table") || sql.include?("missing") }
  end

  test "does not query foreign keys when nothing selected is a known table" do
    source = FakeDatabaseTransferSource.new(foreign_keys: [ fk("child", "parent_id", "parent") ])
    analysis = DatabaseTransfer::DependencyResolver.new(source: source).resolve(
      [ "nope" ],
      known_tables: [ "parent" ]
    )

    assert_empty analysis.selected_tables
    assert_equal [ "nope" ], analysis.ignored_tables
    assert_empty source.statements
  end

  test "reports foreign keys that leave the public table list" do
    analysis = resolve(
      [ "widgets" ],
      %w[widgets],
      [ fk("widgets", "audit_id", "audits", schema: "audit") ]
    )

    assert_empty analysis.required_tables
    assert_equal [ "widgets.audit_id → audit.audits.id" ], analysis.external_dependencies.map(&:summary)
  end

  test "keeps both columns of a composite foreign key" do
    analysis = resolve(
      [ "child" ],
      %w[child parent],
      [
        fk("child", "parent_a", "parent", constraint: "fk_child_parent"),
        fk("child", "parent_b", "parent", constraint: "fk_child_parent")
      ]
    )

    assert_equal [ "parent" ], analysis.required_tables.map(&:name)
    assert_equal %w[parent_a parent_b], analysis.required_tables.first.reasons.map(&:from_column)
  end

  private

  def resolve(selected, known, foreign_keys)
    source = FakeDatabaseTransferSource.new(foreign_keys: foreign_keys)
    DatabaseTransfer::DependencyResolver.new(source: source).resolve(selected, known_tables: known)
  end

  def fk(from, column, to, schema: "public", constraint: nil)
    {
      "from_table" => from,
      "from_column" => column,
      "to_schema" => schema,
      "to_table" => to,
      "to_column" => "id",
      "constraint_name" => constraint || "fk_#{from}_#{column}"
    }
  end
end
