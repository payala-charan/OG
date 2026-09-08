class QuarterStatusesController < ApplicationController
  before_action :require_login

  def index
    @quarter_labels = {
      1 => "Q4 2024",
      2 => "Q1 2025",
      3 => "Q2 2025",
      4 => "Q3 2025",
      5 => "Q4 2025",
      6 => "Q1 2026",
      7 => "Q2 2026"
    }.freeze

    # 1. NewBiosimilarPrice data status
    # Note: array_length(extracted_insurances, 1) is Pg-specific, but safe since we are on Pg.
    @biosimilar_details = NewBiosimilarPrice.group(:team_id, :accounting_period_id).select(
      "team_id, accounting_period_id,
       COUNT(*) as total,
       COUNT(CASE WHEN extracted_brand_name IS NOT NULL AND extracted_brand_name != '' THEN 1 END) as with_brand,
       COUNT(CASE WHEN extracted_strength IS NOT NULL AND extracted_strength != '' THEN 1 END) as with_strength,
       COUNT(CASE WHEN extracted_insurances IS NOT NULL AND array_length(extracted_insurances, 1) > 0 THEN 1 END) as with_insurances"
    ).order(:team_id, :accounting_period_id).each_with_object({}) do |record, hash|
      hash[[record.team_id.to_s, record.accounting_period_id.to_i]] = {
        total: record.total.to_i,
        with_brand: record.with_brand.to_i,
        with_strength: record.with_strength.to_i,
        with_insurances: record.with_insurances.to_i
      }
    end

    # 2. Payor data status
    @payor_details = Payor.group(:team_id, :accounting_period_id)
                          .order(:team_id, :accounting_period_id)
                          .count
                          .each_with_object({}) do |((team, period), count), hash|
      hash[[team.to_s, period.to_i]] = count
    end

    # 3. PayorPreference data status
    @preference_details = PayorPreference.group(:team_id, :accounting_period_id)
                                         .order(:team_id, :accounting_period_id)
                                         .count
                                         .each_with_object({}) do |((team, period), count), hash|
      hash[[team.to_s, period.to_i]] = count
    end

    # Compile a unique list of all [team_id, accounting_period_id] combinations across all tables
    all_combinations = (@biosimilar_details.keys + @payor_details.keys + @preference_details.keys).uniq.sort_by { |team, period| [team.to_s, period.to_i] }
    
    @quarter_statuses = all_combinations.map do |team, period|
      {
        team_id: team,
        accounting_period_id: period,
        quarter_name: @quarter_labels[period] || "Quarter #{period}",
        biosimilar: @biosimilar_details[[team, period]] || { total: 0, with_brand: 0, with_strength: 0, with_insurances: 0 },
        payor_count: @payor_details[[team, period]] || 0,
        preference_count: @preference_details[[team, period]] || 0
      }
    end
  end
end
