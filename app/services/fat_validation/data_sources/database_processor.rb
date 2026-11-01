# frozen_string_literal: true

module FatValidation
  module DataSources
    # Reference rows for a validation run. Overview is the only report with rules.
    class DatabaseProcessor
      def initialize(run:, generic_groups:)
        @run = run
        @generic_groups = generic_groups
      end

      def call
        case @run.report_type
        when "overview"
          Calculators::OverviewCalculator.new(
            team_id: @run.team_id,
            accounting_period_id: @run.accounting_period_id
          ).call(@generic_groups)
        else
          raise Error, "#{@run.report_type} does not have calculation rules yet."
        end
      end
    end
  end
end
