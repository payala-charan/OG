# frozen_string_literal: true

require "test_helper"

class FatValidation::ExcelProcessorTest < ActiveSupport::TestCase
  test "does not guess an excel layout" do
    run = FatValidationRun.new(report_type: "overview", data_source: "excel")

    error = assert_raises(FatValidation::ExcelNotConfigured) do
      FatValidation::DataSources::ExcelProcessor.new(run: run).call
    end
    assert_match "not configured", error.message
  end
end
