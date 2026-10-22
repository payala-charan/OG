# frozen_string_literal: true

module UtilizationAnalytics
  # Builds the analytics query from the screen's controls.
  # Quarter, month, and date range are sent one at a time so a leftover
  # period pair cannot take priority over the control the user is using.
  class Query
    FILTER_KEYS = %i[
      group period_kind time_period trend_grain
      quarter_name1 quarter_name2
      data_month1 data_month2
      start_date end_date
      charge_class hospital_names payor_names
    ].freeze

    def self.any_filter?(params)
      FILTER_KEYS.any? { |key| Array(params[key]).any? { |value| value.present? } }
    end

    def self.period_kind(params)
      kind = params[:period_kind].to_s
      return kind if %w[quarter month date_range].include?(kind)

      return "quarter" if present?(params[:quarter_name1]) && present?(params[:quarter_name2])
      return "month" if present?(params[:data_month1]) && present?(params[:data_month2])
      return "date_range" if present?(params[:start_date]) && present?(params[:end_date])

      params[:time_period].to_s == "month" ? "month" : "quarter"
    end

    def self.team_id_for(value)
      text = value.to_s
      TEAM_IDS.include?(text) ? text : DEFAULT_TEAM_ID
    end

    def self.build(team_id:, params:, applied:)
      query = { "team_id" => team_id_for(team_id) }
      return query unless applied

      copy(query, "group", params[:group])
      copy(query, "charge_class", params[:charge_class])
      copy_list(query, "hospital_names", params[:hospital_names])
      copy_list(query, "payor_names", params[:payor_names])

      case period_kind(params)
      when "month"
        query["time_period"] = "month"
        copy(query, "data_month1", params[:data_month1])
        copy(query, "data_month2", params[:data_month2])
      when "date_range"
        query["time_period"] = params[:trend_grain].to_s == "month" ? "month" : "quarter"
        copy(query, "start_date", params[:start_date])
        copy(query, "end_date", params[:end_date])
      else
        query["time_period"] = "quarter"
        copy(query, "quarter_name1", params[:quarter_name1])
        copy(query, "quarter_name2", params[:quarter_name2])
      end

      query
    end

    def self.present?(value)
      value.respond_to?(:present?) ? value.present? : !value.nil? && value != ""
    end
    private_class_method :present?

    def self.copy(query, key, value)
      text = value.to_s
      query[key] = text if text.present?
    end
    private_class_method :copy

    def self.copy_list(query, key, value)
      items = Array(value).map(&:to_s).reject(&:blank?)
      query[key] = items if items.any?
    end
    private_class_method :copy_list
  end
end
