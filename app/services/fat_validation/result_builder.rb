# frozen_string_literal: true

module FatValidation
  class ResultBuilder
    def initialize(run)
      @run = run
    end

    def save!(comparisons)
      FatValidationRun.transaction do
        comparisons.each do |row|
          @run.results.create!(
            generic_group: row[:generic_group],
            column_name: row[:column_name],
            expected_value: row[:expected_value],
            actual_value: row[:actual_value],
            difference: row[:difference],
            status: row[:status],
            details: row[:details] || {}
          )
        end

        passed = comparisons.count { |row| row[:status] == "PASS" }
        @run.update!(
          status: :completed,
          total_records: comparisons.size,
          passed_records: passed,
          failed_records: comparisons.size - passed,
          completed_at: Time.current,
          progress_message: "Saving results"
        )
      end
    end
  end
end
