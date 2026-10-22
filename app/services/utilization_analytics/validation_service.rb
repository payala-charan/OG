# frozen_string_literal: true

module UtilizationAnalytics
  # Compares the analytics already loaded from the external endpoint with
  # values calculated from this application's database. It does not replace
  # or refetch the endpoint payload.
  class ValidationService
    METRICS = [
      { "key" => "total_units", "name" => "Total Units", "field" => :units, "kind" => :number },
      { "key" => "product_cost_per_unit", "name" => "Product Cost Per Unit", "field" => :cost_per_unit, "kind" => :number, "error" => :cost_error },
      { "key" => "product_cost", "name" => "Total Product Cost", "field" => :product_cost, "kind" => :number, "error" => :cost_error },
      { "key" => "total_margin", "name" => "Total Margin", "field" => :total_margin, "kind" => :number, "error" => :cost_error },
      { "key" => "margin_per_unit", "name" => "Margin Per Unit", "field" => :margin_per_unit, "kind" => :number, "error" => :margin_per_unit_error },
      { "key" => "margin_percent_of_cost", "name" => "Margin % of Cost", "field" => :margin_percent, "kind" => :number, "error" => :margin_percent_error }
    ].freeze

    def initialize(team_id:, params:, analytics_data:)
      @team_id = Query.team_id_for(team_id)
      @params = params
      @analytics = stringify(analytics_data)
    end

    def call
      @periods = selected_periods
      return @periods if @periods.is_a?(Hash)

      comparison = @analytics["comparison"]
      return error("Endpoint data is missing. Run a comparison before verifying.") unless comparison.is_a?(Hash)

      metrics = metric_rows(comparison, @periods) + proof_rows(comparison, @periods)
      return error("Nothing to validate. Run a quarterly or monthly comparison first.") if metrics.empty?

      finish(metrics)
    rescue Periods::UnknownQuarter, ActiveRecord::ActiveRecordError => exception
      error(exception.message)
    end

    private

    attr_reader :team_id, :params

    def selected_periods
      case Query.period_kind(params)
      when "month"
        month_periods
      when "date_range"
        error("Verification is available for monthly and quarterly comparisons.")
      else
        quarter_periods
      end
    end

    def quarter_periods
      baseline = param(:quarter_name1)
      comparator = param(:quarter_name2)
      return error("Select a baseline and comparator quarter before verifying.") if baseline.blank? || comparator.blank?

      [
        Period.quarter(role: "baseline", label: baseline, accounting_period_id: Periods.accounting_period_id(baseline)),
        Period.quarter(role: "comparator", label: comparator, accounting_period_id: Periods.accounting_period_id(comparator))
      ]
    end

    def month_periods
      baseline = param(:data_month1)
      comparator = param(:data_month2)
      return error("Select a baseline and comparator month before verifying.") if baseline.blank? || comparator.blank?

      [
        Period.month(role: "baseline", label: baseline, data_month: baseline),
        Period.month(role: "comparator", label: comparator, data_month: comparator)
      ]
    end

    def metric_rows(comparison, periods)
      METRICS.flat_map do |metric|
        section = comparison[metric["key"]]
        next [] unless section.is_a?(Hash) && section["visible"] == true

        brand_rows(section).flat_map do |row|
          periods.map { |period| metric_result(metric, row, period) }
        end
      end
    end

    def metric_result(metric, row, period)
      measurement = measurements(row["brand"])[period.role]
      message = metric["error"] && measurement.public_send(metric["error"])
      result = if message.present?
        { "status" => "error", "message" => message, "displayed_value" => displayed_number(row, period.role), "db_value" => nil }
      else
        Comparator.compare(
          displayed: displayed_number(row, period.role),
          expected: measurement.public_send(metric["field"]),
          kind: metric["kind"]
        )
      end
      result["message"] = "Endpoint value for #{metric["name"]} is missing." if result["message"] == "Endpoint value is missing."
      context(metric["name"], row["brand"], period).merge(result)
    end

    def proof_rows(comparison, periods)
      rows = []
      units = comparison["total_units"]
      if units.is_a?(Hash) && units["visible"] == true && units.dig("proof", "show_inpatient_row_count") == true
        rows.concat(inpatient_rows(units["proof"], periods))
      end
      cost = comparison["product_cost_per_unit"]
      rows.concat(purchase_line_rows(cost["proof"], periods)) if cost.is_a?(Hash) && cost["visible"] == true && cost["proof"].is_a?(Hash)
      rows
    end

    def inpatient_rows(proof, periods)
      proof_brands(proof).flat_map do |brand, data|
        periods.filter_map do |period|
          key = period.role == "baseline" ? "q1_inpatient_row_count" : "q2_inpatient_row_count"
          next unless data.key?(key)

          count_result("Inpatient lines", brand, period, data[key], measurements(brand).fetch(period.role).inpatient_count)
        end
      end
    end

    def purchase_line_rows(proof, periods)
      proof_brands(proof).flat_map do |brand, data|
        periods.filter_map do |period|
          slot = period.role == "baseline" ? "q1" : "q2"
          details = data[slot]
          next unless details.is_a?(Hash) && details.key?("purchase_lines_included")

          measurement = measurements(brand)[period.role]
          if measurement.cost_error.present?
            context("Purchase lines", brand, period).merge(
              "status" => "error",
              "message" => measurement.cost_error,
              "displayed_value" => details["purchase_lines_included"],
              "db_value" => nil
            )
          else
            count_result("Purchase lines", brand, period, details["purchase_lines_included"], measurement.purchase_line_count)
          end
        end
      end
    end

    def count_result(name, brand, period, displayed, expected)
      context(name, brand, period).merge(
        Comparator.compare(displayed: displayed, expected: expected, kind: :count)
      )
    end

    def measurements(brand)
      @measurements ||= {}
      @measurements[brand.to_s.upcase] ||= @periods.to_h { |period| [ period.role, calculator.measure(brand, period) ] }
    end

    def calculator
      @calculator ||= Calculator.new(
        team_id: team_id,
        group: param(:group),
        charge_class: param(:charge_class),
        hospital_names: Array(param(:hospital_names)),
        payor_names: Array(param(:payor_names))
      )
    end

    def brand_rows(section)
      Array(section["rows"]).select { |row| row.is_a?(Hash) && row["brand"].present? && !row["brand"].to_s.strip.casecmp("total").zero? }
    end

    def proof_brands(proof)
      rows = proof["rows"]
      return [] unless rows.is_a?(Hash)

      rows.map { |brand, data| [ brand.to_s, data.is_a?(Hash) ? data : {} ] }
    end

    def displayed_number(row, role)
      value = row[role]
      return value.to_f if value.is_a?(Numeric)

      parse_display(row["#{role}_display"])
    end

    def parse_display(value)
      text = value.to_s.strip
      return nil if text.blank?

      negative = text.start_with?("(") && text.end_with?(")")
      cleaned = text.gsub(/[^\d.\-]/, "")
      return nil if cleaned.blank? || cleaned == "-" || cleaned == "."

      number = cleaned.to_f
      negative ? -number.abs : number
    end

    def context(metric, brand, period)
      {
        "metric" => metric,
        "brand" => brand.to_s,
        "period" => period.role,
        "period_label" => period.label
      }
    end

    def finish(metrics)
      status = if metrics.any? { |row| row["status"] == "failed" }
        "failed"
      elsif metrics.any? { |row| row["status"] == "error" }
        "error"
      else
        "passed"
      end
      message = { "passed" => "Validation Passed", "failed" => "Validation Failed" }[status]
      message ||= metrics.find { |row| row["message"].present? }&.dig("message") || "Validation could not be completed."
      { "status" => status, "message" => message, "metrics" => metrics }
    end

    def error(message)
      { "status" => "error", "message" => message, "metrics" => [] }
    end

    def param(key)
      params[key].nil? ? params[key.to_s] : params[key]
    end

    def stringify(value)
      case value
      when nil
        {}
      when String
        JSON.parse(value)
      else
        JSON.parse(value.to_json)
      end
    rescue JSON::ParserError, NoMethodError
      {}
    end
  end
end
