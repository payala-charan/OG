# frozen_string_literal: true

class DatabaseTransferJob < ApplicationJob
  queue_as :default

  # The executor records its own failures and claims the run once, so a retry
  # could never do more than report "already claimed".
  discard_on StandardError

  def perform(run_id)
    run = DatabaseTransferRun.find_by(id: run_id)
    return unless run

    DatabaseTransfer::Executor.new(run).call
  end
end
