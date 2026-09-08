# frozen_string_literal: true

require "google/apis/gmail_v1"

# Fetches sent messages from Gmail for a recipient in a date range, using
# the Sent label and the Gmail list/get APIs with pagination.
class GmailFetcher
  MAX_PER_PAGE = 100

  def self.build_query(recipient_email:, start_on:, end_on:)
    to_term = format_to_query(recipient_email)
    # `before` is exclusive in Gmail; add one day so `end_on` is inclusive
    start_s = start_on.strftime("%Y/%m/%d")
    before_s = (end_on + 1.day).strftime("%Y/%m/%d")
    [ "in:sent", to_term, "after:#{start_s}", "before:#{before_s}" ].join(" ")
  end

  def self.format_to_query(email)
    s = email.to_s.strip
    if /[\s"()]/.match?(s) || s.include?(":")
      %("#{s.gsub('"', "\\\"")}")
    else
      s
    end
  end

  def initialize(gmail_connection:, recipient_email:, start_on:, end_on:)
    @connection = gmail_connection
    @recipient_email = recipient_email
    @start_on = start_on
    @end_on = end_on
  end

  # Yields a hash: :gmail_message_id, :subject, :body_text, :sent_at
  def each_message
    query = self.class.build_query(
      recipient_email: @recipient_email,
      start_on: @start_on,
      end_on: @end_on
    )
    page = nil
    loop do
      res = list_messages_paged(query, page)
      (res.messages || []).each do |ref|
        msg = get_message_fresh(ref.id)
        yield build_row(msg)
      end
      page = res.next_page_token
      break if page.blank?
    end
  end

  private

  def build_row(message)
    {
      gmail_message_id: message.id,
      subject: subject_from_message(message),
      body_text: extract_body(message.payload).to_s.strip,
      sent_at: time_from_message(message)
    }
  end

  def time_from_message(message)
    if message.internal_date
      t = message.internal_date.to_f / 1000.0
      Time.zone.at(t)
    end
  end

  def subject_from_message(message)
    message.payload.headers&.find { |h| h.name.to_s.casecmp?("Subject") }&.value.to_s
  end

  def list_messages_paged(query, page)
    with_auth_retry do |svc|
      svc.list_user_messages("me", q: query, max_results: MAX_PER_PAGE, page_token: page)
    end
  end

  def get_message_fresh(id)
    with_auth_retry { |svc| svc.get_user_message("me", id, format: "full") }
  end

  def with_auth_retry
    @connection.ensure_valid_token!
    service = @connection.gmail_service
    yield service
  rescue Google::Apis::Error, Signet::AuthorizationError => e
    raise unless auth_error?(e)

    @connection.reload
    @connection.ensure_valid_token!
    service = @connection.gmail_service
    yield service
  end

  def auth_error?(e)
    code = e.respond_to?(:status_code) ? e.status_code.to_i : 0
    return true if code == 401

    e.message.to_s.match?(/unauthorized|invalid|401|Credentials|invalid_grant|token/i)
  end

  def extract_body(part)
    return "" if part.nil?

    plain, html = bodies_from_part(part, plain: +"", html: +"")
    return plain if plain.present?
    return GmailHtmlToText.convert(html) if html.present?
    ""
  end

  def bodies_from_part(part, plain:, html:)
    case part.mime_type&.downcase
    when "text/plain"
      plain << decode_body(part) if part.body&.data
    when "text/html"
      html << decode_body(part) if part.body&.data
    when "multipart/alternative", "multipart/mixed", "multipart/related", "multipart/signed", "message/rfc822", "application/pgp-encrypted", nil
      (part.parts || []).each { |p| bodies_from_part(p, plain: plain, html: html) }
    else
      (part.parts || []).each { |p| bodies_from_part(p, plain: plain, html: html) }
    end
    [ plain, html ]
  end

  def decode_body(part)
    data = part.body.data
    enc = part.body.encoding
    s = if enc && enc.to_s.casecmp?("base64")
      Base64.decode64(data)
    else
      decode_gmail_data(data)
    end
    s = s.dup if s.frozen?
    s.force_encoding("UTF-8")
  rescue StandardError
    part.body&.data.to_s
  end

  def decode_gmail_data(data)
    return "" if data.nil?
    s = data.tr("-_", "+/")
    s += "=" * ((4 - s.length % 4) % 4)
    Base64.decode64(s)
  end
end

# HTML parts → readable plain text
module GmailHtmlToText
  module_function

  def convert(html)
    return "" if html.blank?
    s = Nokogiri::HTML::DocumentFragment.parse(html).text
    s.gsub("\u00a0", " ").gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
  end
end
