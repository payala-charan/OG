# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module UtilizationAnalytics
  class Client
    class Error < StandardError; end

    class Unauthorized < Error; end

    class InvalidParams < Error
      attr_reader :payload

      def initialize(message, payload = {})
        super(message)
        @payload = payload
      end
    end

    def fetch(query)
      encoded = encode(query)
      uri = endpoint
      response = encoded.bytesize > 1_800 ? post_form(uri, encoded) : get_query(uri, encoded)
      interpret(response)
    end

    def self.base_url
      ENV.fetch("BASE_URL", "http://localhost:3000").chomp("/")
    end

    private

    def endpoint
      URI("#{self.class.base_url}/api/utilization_analytics")
    end

    def encode(query)
      pairs = []
      query.each do |key, value|
        if key.to_s.end_with?("_names")
          Array(value).each { |item| pairs << [ "#{key}[]", item ] }
        else
          pairs << [ key.to_s, value ] unless value.nil?
        end
      end
      URI.encode_www_form(pairs)
    end

    def get_query(uri, encoded)
      target = uri.dup
      target.query = encoded
      with_http(target) do |http|
        request = Net::HTTP::Get.new(target)
        request["Accept"] = "application/json"
        http.request(request)
      end
    end

    def post_form(uri, encoded)
      with_http(uri) do |http|
        request = Net::HTTP::Post.new(uri.request_uri)
        request["Accept"] = "application/json"
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = encoded
        http.request(request)
      end
    end

    def with_http(uri)
      Net::HTTP.start(
        uri.host,
        uri.port,
        use_ssl: uri.scheme == "https",
        open_timeout: 15,
        read_timeout: 60
      ) do |http|
        yield http
      end
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError,
           Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => error
      raise Error, "Could not reach utilization analytics. #{error.message}"
    end

    def interpret(response)
      payload = parse_json(response.body)
      case response.code.to_i
      when 200
        raise Error, "Unexpected utilization analytics response." unless payload.is_a?(Hash)

        payload
      when 401
        raise Unauthorized, error_text(payload, "Unauthorized")
      when 422
        raise InvalidParams.new(error_text(payload, "A date parameter was invalid."), payload.is_a?(Hash) ? payload : {})
      else
        raise Error, error_text(payload, "Utilization analytics request failed (#{response.code}).")
      end
    end

    def parse_json(body)
      return {} if body.blank?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def error_text(payload, fallback)
      return fallback unless payload.is_a?(Hash)

      case payload["error"]
      when String
        payload["error"].presence || fallback
      when Array
        payload["error"].map(&:to_s).join(", ").presence || fallback
      else
        fallback
      end
    end
  end
end
