# frozen_string_literal: true

# Run with Sidekiq: `bundle exec sidekiq` and Redis (REDIS_URL, default redis://localhost:6379/0)
class GmailExtractionJob
  include Sidekiq::Job
  sidekiq_options queue: "default", retry: 2

  BATCH_SIZE = 200

  def perform(gmail_extraction_id)
    extraction = GmailExtraction.eager_load(:gmail_connection).find(gmail_extraction_id)
    extraction.update!(status: "running", error_message: nil, total_fetched: 0)

    connection = extraction.gmail_connection
    now = Time.current
    count = 0
    batch = []

    fetcher = GmailFetcher.new(
      gmail_connection: connection,
      recipient_email: extraction.recipient_email,
      start_on: extraction.start_on,
      end_on: extraction.end_on
    )

    fetcher.each_message do |row|
      batch << GmailExtractedEmail.new(
        gmail_extraction_id: extraction.id,
        gmail_message_id: row[:gmail_message_id],
        subject: row[:subject].to_s.truncate(500),
        body_text: row[:body_text].presence || "",
        sent_at: row[:sent_at],
        created_at: now,
        updated_at: now
      )
      count += 1
      if batch.size >= BATCH_SIZE
        import_batch!(batch)
        batch.clear
      end
    end
    import_batch!(batch) if batch.any?

    extraction.update!(status: "completed", total_fetched: count)
  rescue StandardError => e
    GmailExtraction.find_by(id: gmail_extraction_id)&.update(
      status: "failed",
      error_message: "#{e.class}: #{e.message}".truncate(2000)
    )
    raise
  end

  private

  def import_batch!(batch)
    return if batch.empty?

    GmailExtractedEmail.import(
      batch,
      validate: false,
      on_duplicate_key_ignore: true
    )
  end
end
