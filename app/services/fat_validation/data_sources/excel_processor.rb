# frozen_string_literal: true

module FatValidation
  module DataSources
    # Excel column mapping for Overview has not been provided yet.
    class ExcelProcessor
      def initialize(run:)
        @run = run
      end

      def call
        raise ExcelNotConfigured, "Excel extraction for Overview is not configured yet."
      end
    end
  end
end
