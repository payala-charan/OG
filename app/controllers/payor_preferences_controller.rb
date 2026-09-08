class PayorPreferencesController < ApplicationController
  helper_method :get_payor_color_class
  QUARTER_LABELS = {
      1 => "Q4 2024",
      2 => "Q1 2025",
      3 => "Q2 2025",
      4 => "Q3 2025",
      5 => "Q4 2025"
    }.freeze

  def index
    @payor_preferences = PayorPreference
      .order(
        :accounting_period_id,
        :generic_name_group,
        :payor,
        :strength
      )
    @accounting_period_counts = PayorPreference.group(:accounting_period_id).count
    counts = PayorPreference.group(:accounting_period_id).count

    @chart_data = counts.map do |period_id, count|
      {
        name: QUARTER_LABELS[period_id],
        y: count
      }
    end

  end

  def show
    @payor_preference = PayorPreference.find(params[:id])
  end

  def strengths
    group = params[:generic_name_group]
    strengths = PayorPreference.where(generic_name_group: group.upcase).pluck(:strength).uniq.sort
    render json: strengths
  end


  private

  def get_payor_color_class(payor)
    name = payor.to_s.downcase
    if name.include?('medicare')
      'payor-medicare'
    elsif name.include?('medicaid')
      'payor-medicaid'
    elsif name.include?('private')
      'payor-private'
    elsif name.include?('anthem')
      'payor-anthem'
    elsif name.include?('united')
      'payor-united'
    elsif name.include?('cigna')
      'payor-cigna'
    elsif name.include?('aetna')
      'payor-aetna'
    elsif name.include?('humana')
      'payor-humana'
    elsif name.include?('bluecross') || name.include?('blue cross')
      'payor-bluecross'
    else
      "payor-#{name.parameterize}"
    end
  end
end