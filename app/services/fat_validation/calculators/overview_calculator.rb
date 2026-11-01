# frozen_string_literal: true

module FatValidation
  module Calculators
    # Opportunity for one generic group on the Overview screen.
    #
    # ids = UtilizationReport.where(
    #   team_id:, accounting_period_id:, category: nil, generic_name_group:
    # ).pluck(:id)
    #
    # InvoiceConversion.where(
    #   utilization_report_id: ids,
    #   team_id:,
    #   conversion_type: "highest_margin",
    #   status: "individual"
    # ).pluck(:blended_conversion_margin_difference).compact.sum.to_i
    class OverviewCalculator
      CONVERSION_TYPE = "highest_margin"
      CONVERSION_STATUS = "individual"

      def initialize(team_id:, accounting_period_id:, reports: nil, conversions: nil)
        @team_id = team_id.to_s
        @accounting_period_id = accounting_period_id
        @reports = reports
        @conversions = conversions
      end

      def call(generic_groups)
        Array(generic_groups).uniq.map { |group| opportunity_for(group) }
      end

      private

      def opportunity_for(group)
        name = group.to_s
        ids = report_scope.where(
          team_id: @team_id,
          accounting_period_id: @accounting_period_id,
          category: nil,
          generic_name_group: name
        ).pluck(:id)

        values = if ids.empty?
          []
        else
          conversion_scope.where(
            utilization_report_id: ids,
            team_id: @team_id,
            conversion_type: CONVERSION_TYPE,
            status: CONVERSION_STATUS
          ).pluck(:blended_conversion_margin_difference)
        end

        {
          generic_group: name,
          column_name: FatValidation::OPPORTUNITY_COLUMN,
          expected_value: values.compact.sum.to_i,
          details: {
            "utilization_report_count" => ids.size,
            "invoice_conversion_count" => values.size,
            "conversion_type" => CONVERSION_TYPE,
            "conversion_status" => CONVERSION_STATUS,
            "accounting_period_id" => @accounting_period_id
          }
        }
      end

      def report_scope
        @reports || UtilizationAnalytics::Tables.utilization_reports
      end

      def conversion_scope
        @conversions || UtilizationAnalytics::Tables.relation("invoice_conversions")
      end
    end
  end
end
