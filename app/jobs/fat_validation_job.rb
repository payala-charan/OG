# frozen_string_literal: true

class FatValidationJob < ApplicationJob
  queue_as :default

  def perform(run_id, visible: true)
    run = FatValidationRun.find_by(id: run_id)
    return if run.nil? || run.completed? || run.failed?

    FatValidation::Runner.new(run, visible: visible).call
  end
end
