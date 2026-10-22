# frozen_string_literal: true

module DatabaseTransfer
  # Starts a transfer run in the background.
  #
  # Uses Solid Queue when its tables exist. Local development has the adapter
  # configured but no queue tables or worker, so the run executes in a thread.
  # Either way it runs exactly once: the executor claims the run atomically.
  class Dispatcher
    def self.start(run)
      new.start(run)
    end

    def start(run)
      if solid_queue_ready?
        DatabaseTransferJob.perform_later(run.id)
      elsif Rails.env.test?
        nil
      else
        Thread.new do
          Rails.application.executor.wrap { DatabaseTransferJob.perform_now(run.id) }
        end
      end
    end

    private

    def solid_queue_ready?
      adapter = ActiveJob::Base.queue_adapter
      return false unless adapter.class.name.include?("SolidQueue")

      connection = defined?(SolidQueue::Job) ? SolidQueue::Job.connection : ActiveRecord::Base.connection
      connection.data_source_exists?("solid_queue_jobs")
    rescue StandardError
      false
    end
  end
end
