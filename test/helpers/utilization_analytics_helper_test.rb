# frozen_string_literal: true

require "test_helper"

class UtilizationAnalyticsHelperTest < ActionView::TestCase
  test "maps a full comparison row onto the display fields" do
    fields = ua_display_fields([ "Brand", "Quarter 4 2025", "Quarter 1 2026", "Total", "Difference" ])

    assert_equal %w[brand baseline_display comparator_display total_display difference_display], fields
  end

  test "margin percent has no total column" do
    fields = ua_display_fields([ "Brand", "Quarter 4 2025", "Quarter 1 2026", "Difference" ])

    assert_equal %w[brand baseline_display comparator_display difference_display], fields
  end

  test "a four column table still keeps the last cell as the difference" do
    fields = ua_display_fields([ "Brand", "Q4", "Q1", "Change" ])

    assert_equal %w[brand baseline_display comparator_display difference_display], fields
  end

  test "lists the source groups, quarters, and months from September 2025 through January 2027" do
    assert_equal "PEGFILGRASTIM", ua_group_options.first
    assert_includes ua_group_options, "HYALURONATE SODIUM"
    assert_includes ua_group_options, "TRASTUZUMAB"
    assert_equal [ "Quarter 4 2025", "Quarter 1 2026", "Quarter 2 2026", "Quarter 3 2026" ], ua_quarter_options
    assert_equal "September 2025", ua_month_options.first
    assert_equal "January 2027", ua_month_options.last
    assert_equal 17, ua_month_options.size
  end

  test "the team dropdown defaults to 209" do
    assert_equal "209", ua_team_id
    assert_equal %w[198 209 147], UtilizationAnalytics::TEAM_IDS
  end

  test "outpatient is labeled for the screen" do
    assert_equal "Outpatient / Emergency", ua_charge_class_label("Outpatient")
    assert_equal "Inpatient", ua_charge_class_label("Inpatient")
  end

  test "formats proof numbers the way the calculation sheet shows them" do
    assert_equal "0", ua_proof_number(0)
    assert_equal "3550.0", ua_proof_number(3550.0)
    assert_equal "3290.2", ua_proof_number(3290.2)
    assert_equal "19108.6", ua_proof_number(19_108.6)
    assert_equal "$1,250.00", ua_proof_money(1250)
    assert_equal "20.00%", ua_proof_percent(20)
  end

  test "recognizes a calculation proof only when the section has rows" do
    proof = { "rows" => { "AVASTIN" => { "q1_table_total" => 1 } } }

    assert_equal "cms", ua_proof_kind("total_units", proof)
    assert_equal "product_cost", ua_proof_kind("product_cost", proof)
    assert_nil ua_proof_kind("total_units", { "steps" => [ "PROOF-LINE" ] })
    assert_equal [ [ "AVASTIN", { "q1_table_total" => 1 } ] ], ua_proof_rows(proof)
  end
end
