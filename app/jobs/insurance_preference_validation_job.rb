# frozen_string_literal: true

class InsurancePreferenceValidationJob < ApplicationJob
  queue_as :default

  def perform(run_id)
    run = InsurancePreferenceValidationRun.find(run_id)
    InsurancePreference::Runner.new(run).call
  end
end
