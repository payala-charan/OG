# frozen_string_literal: true

require "test_helper"

class InsurancePreference::MatchingRulesTest < ActiveSupport::TestCase
  test "group inference is most-specific-first" do
    assert_equal "PEGFILGRASTIM", InsurancePreference::GroupInference.infer("Pegfilgrastim-jmdb (Fulphila)")
    assert_equal "FILGRASTIM", InsurancePreference::GroupInference.infer("TBO-Filgrastim 300mcg/0.5ml Syringe")
    assert_equal "FILGRASTIM", InsurancePreference::GroupInference.infer("Filgrastim (Neupogen)")
    assert_equal "TOCILIZUMAB", InsurancePreference::GroupInference.infer("Actemra 200mg")
    assert_equal "LEUPROLIDE ACETATE", InsurancePreference::GroupInference.infer("Leuprolide Depot 3 Month")
  end

  test "group names match after word-order normalization" do
    tabs = [
      InsurancePreference::MasterParser::TabResult.new(name: "HYALURONATE SODIUM", columns: [], required_by_identity: {})
    ]
    resolver = InsurancePreference::TabResolver.new(tabs)

    assert resolver.resolve("SODIUM HYALURONATE")
    assert_equal "HYALURONATE SODIUM", resolver.resolve("SODIUM HYALURONATE").name
  end

  test "leuprolide matcher requires family and exact month" do
    columns = [
      header("Lupron Depot 1 Month J1950"),
      header("Lupron Depot 3 Month J1950"),
      header("Eligard 3 Month J1950")
    ]
    matcher = InsurancePreference::BrandMatcher.new(columns)
    match = matcher.match(
      generic_name: "Leuprolide (Lupron Depot) 3 Month Injection",
      group: "LEUPROLIDE ACETATE",
      tab_found: true
    )

    assert_equal "OK", match.method
    assert_equal "Lupron Depot 3 Month", match.brand.core
    refute_equal "Lupron Depot 1 Month", match.brand.core
  end

  test "score below 0.65 is NO_MATCH rather than a low-confidence guess" do
    columns = [header("Synvisc J7325")]
    matcher = InsurancePreference::BrandMatcher.new(columns)
    match = matcher.match(
      generic_name: "Sodium Hyaluronate (Genvisc 850) 25mg/2.5ml",
      group: "HYALURONATE SODIUM",
      tab_found: true
    )

    assert_equal "NO_MATCH", match.method
    assert_nil match.brand
    assert match.confidence < 0.65
  end

  test "infliximab In-Fliximab override maps to Generic Remicade" do
    columns = [
      header("Remicade J1745"),
      header("Generic Remicade J1745"),
      header("Inflectra Q5103")
    ]
    matcher = InsurancePreference::BrandMatcher.new(columns)
    match = matcher.match(
      generic_name: "Infliximab (In-Fliximab) 100mg Injection",
      group: "INFLIXIMAB",
      tab_found: true
    )

    assert_equal "OVERRIDE", match.method
    assert_match(/Generic Remicade/i, match.brand.raw_header)
  end

  test "unbranded candidate retries with Generic suffix" do
    columns = [header("Bendamustine Generic J9033"), header("Treanda J9033")]
    matcher = InsurancePreference::BrandMatcher.new(columns)
    match = matcher.match(
      generic_name: "Bendamustine 100mg Injection",
      group: "BENDAMUSTINE",
      tab_found: true
    )

    assert_equal "OK", match.method
    assert_match(/Generic/i, match.brand.core)
  end

  test "special display overrides always render red" do
    required = ["INNOVAGE (PACE)", "GOVT EMP HOSPITAL ASSC.", "AETNA PPO"]
    comparison = InsurancePreference::InsuranceComparator.new(required, required).call
    runs = InsurancePreference::ClaudeCellBuilder.build(required, comparison)

    rendered = runs.map { |run| [run.text, run.color] }
    assert rendered.any? { |text, color| text.include?("INNOVAGE (PACE)") && color == "red" }
    assert rendered.any? { |text, color| text.include?("GOVT EMP HOSPITAL ASSC") && !text.include?("ASSC.") && color == "red" }
    assert rendered.any? { |text, color| text.include?("AETNA PPO") && color == "black" }
  end

  private

  def header(raw)
    InsurancePreference::MasterParser.parse_header(raw)
  end
end
