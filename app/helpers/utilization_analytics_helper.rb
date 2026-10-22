# frozen_string_literal: true

module UtilizationAnalyticsHelper
  SECTION_KEYS = %w[
    total_units
    product_cost
    product_cost_per_unit
    total_margin
    margin_per_unit
    margin_percent_of_cost
  ].freeze

  CHART_KEYS = %w[drug_spend margin_improvement].freeze

  PERIOD_FIELDS = %w[quarter_name1 quarter_name2 data_month1 data_month2 start_date end_date].freeze

  GENERIC_NAME_GROUPS = [
    "PEGFILGRASTIM",
    "BEVACIZUMAB",
    "INFLIXIMAB",
    "BENDAMUSTINE",
    "FILGRASTIM",
    "HYALURONATE SODIUM",
    "LEUPROLIDE ACETATE",
    "RITUXIMAB",
    "TOCILIZUMAB",
    "TRASTUZUMAB"
  ].freeze

  QUARTERS = [
    "Quarter 4 2025",
    "Quarter 1 2026",
    "Quarter 2 2026",
    "Quarter 3 2026"
  ].freeze

  def ua_filters
    value = ua_payload["filters"]
    value.is_a?(Hash) ? value : {}
  end

  def ua_api_selected
    @ua_api_selected ||= begin
      selected = ua_filters["selected"]
      selected.is_a?(Hash) ? selected.stringify_keys : {}
    end
  end

  def ua_comparison
    value = ua_payload["comparison"]
    value.is_a?(Hash) ? value : {}
  end

  def ua_trending
    value = ua_payload["trending"]
    value.is_a?(Hash) ? value : {}
  end

  def ua_mode
    ua_payload["mode"].to_s
  end

  def ua_render_comparison?
    %w[quarter month date_range].include?(ua_mode) && ua_payload["comparison"].is_a?(Hash)
  end

  def ua_show_tables?
    %w[quarter month].include?(ua_mode)
  end

  def ua_messages
    [ ua_filters["message"], ua_payload["message"] ].select(&:present?).uniq
  end

  def ua_applied?
    params[:analytics_request].present? || UtilizationAnalytics::Query.any_filter?(params)
  end

  def ua_period_kind
    if ua_applied?
      UtilizationAnalytics::Query.period_kind(params)
    elsif ua_mode == "date_range"
      "date_range"
    else
      time_period = ua_api_selected["time_period"].presence || ua_payload["time_period"].presence
      time_period == "month" ? "month" : "quarter"
    end
  end

  def ua_trend_grain
    if ua_period_kind == "date_range"
      value = ua_api_selected["time_period"].presence || ua_payload["time_period"].presence || params[:trend_grain]
      value.to_s == "month" ? "month" : "quarter"
    else
      params[:trend_grain].to_s == "month" ? "month" : "quarter"
    end
  end

  def ua_value(key)
    selected = ua_api_selected
    return params[key] if ua_inactive?(key) && params.key?(key)
    return selected[key] if selected.key?(key)

    params[key]
  end

  def ua_values(key)
    selected = ua_api_selected
    source = if ua_inactive?(key) && params.key?(key)
      params[key]
    elsif selected.key?(key)
      selected[key]
    elsif ua_applied? && params.key?(key)
      params[key]
    else
      []
    end
    Array(source).reject(&:blank?).map(&:to_s)
  end

  def ua_choices(list, selected = nil)
    values = Array(list).filter_map { |item| ua_choice_value(item) }.uniq
    Array(selected).each do |item|
      text = item.to_s
      values << text if text.present? && values.exclude?(text)
    end
    values
  end

  def ua_charge_class_label(value)
    value.to_s == "Outpatient" ? "Outpatient / Emergency" : value.to_s
  end

  def ua_group_options
    # ua_choices(GENERIC_NAME_GROUPS + Array(ua_filters["generic_name_groups"]), ua_value("group"))
    ua_choices(GENERIC_NAME_GROUPS)
  end

  def ua_quarter_options
    selected = [ ua_quarter_value("quarter_name1"), ua_quarter_value("quarter_name2") ]
    ua_choices(QUARTERS + Array(ua_filters["quarters"]), selected)
  end

  def ua_month_options
    start_on = Date.new(2025, 9, 1)
    end_on = Date.new(2027, 1, 1)
    months = []
    cursor = start_on
    while cursor <= end_on
      months << cursor.strftime("%B %Y")
      cursor = cursor.next_month
    end
    selected = [ ua_value("data_month1"), ua_value("data_month2") ]
    ua_choices(months + Array(ua_filters["data_months"]), selected)
  end

  def ua_quarter_value(key)
    fallback = key.to_s == "quarter_name1" ? QUARTERS.first : QUARTERS.second
    ua_value(key).presence || fallback
  end

  def ua_selected_charge_class
    value = ua_value("charge_class").presence || ua_payload["charge_class"].presence || "Outpatient"
    value.to_s
  end

  def ua_toggle_period
    if ua_period_kind == "date_range"
      ua_trend_grain
    elsif ua_period_kind == "month"
      "month"
    else
      "quarter"
    end
  end

  def ua_show_scope_filters?
    ua_value("group").present?
  end

  def ua_downloadable?
    ua_render_comparison? || ua_trending_charts.any?
  end

  def ua_location_options
    ua_choices(Array(ua_filters["hospital_names"]), ua_values("hospital_names"))
  end

  def ua_payor_options
    ua_choices(Array(ua_filters["payor_names"]), ua_values("payor_names"))
  end

  def ua_team_id
    UtilizationAnalytics::Query.team_id_for(params[:team_id])
  end

  def ua_page_params(overrides = {})
    query = {
      analytics_request: "1",
      team_id: ua_team_id,
      period_kind: ua_period_kind,
      group: ua_value("group"),
      charge_class: ua_selected_charge_class,
      hospital_names: ua_values("hospital_names"),
      payor_names: ua_values("payor_names")
    }
    case ua_period_kind
    when "month"
      query[:data_month1] = ua_value("data_month1")
      query[:data_month2] = ua_value("data_month2")
    when "date_range"
      query[:start_date] = ua_value("start_date")
      query[:end_date] = ua_value("end_date")
      query[:trend_grain] = ua_trend_grain
    else
      query[:period_kind] = "quarter"
      query[:quarter_name1] = ua_quarter_value("quarter_name1")
      query[:quarter_name2] = ua_quarter_value("quarter_name2")
    end
    query.merge(overrides).compact_blank
  end

  def ua_display_fields(columns)
    headers = Array(columns).map(&:to_s)
    fields = Array.new(headers.size)
    fields[0] = "brand" if headers.any?

    headers.each_with_index do |header, index|
      next if index.zero?

      name = header.strip.downcase
      fields[index] = if name == "total"
        "total_display"
      elsif name.include?("difference")
        "difference_display"
      end
    end

    open_indexes = fields.each_index.select { |index| fields[index].nil? }
    if fields.exclude?("difference_display") && open_indexes.size >= 3
      fields[open_indexes.last] = "difference_display"
      open_indexes = open_indexes[0...-1]
    end

    periods = %w[baseline_display comparator_display]
    open_indexes.each_with_index do |index, offset|
      fields[index] = periods[offset] || "comparator_display"
    end
    fields
  end

  def ua_section_rows(section)
    Array(section["rows"]).select { |row| row.is_a?(Hash) }
  end

  def ua_show_table?(section)
    ua_show_tables? && ua_visible?(section) && Array(section["columns"]).any?
  end

  def ua_chart_node(node)
    return {} unless node.is_a?(Hash)

    chart = node["chart"]
    if chart.is_a?(Hash) && (chart.key?("series") || chart.key?("visible") || chart.key?("title"))
      chart
    else
      node
    end
  end

  def ua_chart_visible?(node)
    ua_visible?(ua_chart_node(node))
  end

  def ua_visible?(node)
    node.is_a?(Hash) && node["visible"] == true
  end

  def ua_chart_for_js(node)
    chart = ua_chart_node(node)
    {
      "title" => chart["title"],
      "x_axis" => chart["x_axis"],
      "y_axis" => chart["y_axis"],
      "series" => chart["series"]
    }
  end

  def ua_trending_charts
    return [] unless ua_trending["visible"] == true

    Array(ua_trending["charts"]).select { |chart| chart.is_a?(Hash) && chart["visible"] != false }
  end

  def ua_period_text(value)
    case value
    when String, Numeric
      value.to_s.presence
    when Hash
      value["name"].presence || value["label"].presence || value["title"].presence
    end
  end

  PROOF_KINDS = {
    "total_units" => "cms",
    "product_cost" => "product_cost",
    "product_cost_per_unit" => "cost_per_unit",
    "total_margin" => "margin",
    "margin_per_unit" => "margin_per_unit",
    "margin_percent_of_cost" => "margin_percent"
  }.freeze

  def ua_proof_kind(section_key, proof)
    return unless proof.is_a?(Hash)

    rows = proof["rows"]
    return unless rows.is_a?(Hash) && rows.any?

    PROOF_KINDS[section_key.to_s]
  end

  def ua_proof_rows(proof)
    proof["rows"].map { |brand, data| [ brand.to_s, data.is_a?(Hash) ? data : {} ] }
  end

  def ua_proof_charge_classes(proof)
    Array(proof["charge_classes"]).map(&:to_s)
  end

  def ua_proof_inpatient_rows?(proof)
    proof["show_inpatient_row_count"] == true
  end

  def ua_proof_period(row, key)
    value = row[key]
    value.is_a?(Hash) ? value : {}
  end

  def ua_proof_grand(proof, period)
    value = proof.dig("grand_totals", period)
    value.is_a?(Hash) ? value : {}
  end

  def ua_proof_purchase(proof, period)
    value = ua_proof_grand(proof, period)["purchase"]
    value.is_a?(Hash) ? value : {}
  end

  def ua_proof_class_total(rows, period, charge_class)
    rows.sum { |_brand, data| ua_proof_period(data, period)[charge_class].to_f }
  end

  def ua_proof_count_total(rows, field)
    rows.sum { |_brand, data| data[field].to_i }
  end

  def ua_proof_number(value)
    rounded = value.to_f.round(2)
    return "0" if rounded.zero?
    return format("%.1f", rounded) if rounded == rounded.to_i

    format("%.2f", rounded).sub(/0\z/, "")
  end

  def ua_proof_money(value)
    number_to_currency(value.to_f.round(2), precision: 2)
  end

  def ua_proof_percent(value)
    number_to_percentage(value.to_f, precision: 2)
  end

  private

  def ua_payload
    payload = @payload
    payload.is_a?(Hash) ? payload : {}
  end

  def ua_inactive?(key)
    return false unless ua_applied?
    return false unless PERIOD_FIELDS.include?(key.to_s)

    active = case ua_period_kind
    when "month" then %w[data_month1 data_month2]
    when "date_range" then %w[start_date end_date]
    else %w[quarter_name1 quarter_name2]
    end
    active.exclude?(key.to_s)
  end

  def ua_choice_value(item)
    case item
    when String, Numeric
      item.to_s.presence
    when Hash
      (item["name"] || item["label"] || item["value"]).to_s.presence
    end
  end
end
