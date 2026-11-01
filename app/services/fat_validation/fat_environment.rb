# frozen_string_literal: true

module FatValidation
  # Allowlisted FAT origins and the login that belongs to each team.
  # Passwords come only from environment variables.
  class FatEnvironment
    ENVIRONMENTS = {
      "local" => "FAT_LOCAL_URL",
      "staging" => "FAT_STAGING_URL",
      "production" => "FAT_PRODUCTION_URL"
    }.freeze

    DEFAULT_URLS = {
      "local" => "http://localhost:3000",
      "staging" => "https://stg-savings.inpharmd.ai",
      "production" => "https://savings.inpharmd.ai"
    }.freeze

    TEAMS = {
      "198" => { email: "steve+rsa@inpharmd.com", password_env: "FAT_TEAM_198_PASSWORD" },
      "209" => { email: "steve+charles@inpharmd.com", password_env: "FAT_TEAM_209_PASSWORD" },
      "147" => { email: "steve+kettering@inpharmd.com", password_env: "FAT_TEAM_147_PASSWORD" }
    }.freeze

    def self.team_options
      TEAMS.map { |team_id, team| [ "#{team_id} — #{team[:email]}", team_id ] }
    end

    def self.secret_values
      TEAMS.flat_map { |_id, team| [ team[:email], ENV[team[:password_env]] ] }.compact_blank
    end

    def initialize(environment:, team_id:)
      @environment = environment.to_s
      @team_id = team_id.to_s
      raise ConfigurationError, "Choose Local, Staging, or Production." unless ENVIRONMENTS.key?(@environment)
      raise ConfigurationError, "Choose a team." unless TEAMS.key?(@team_id)
    end

    attr_reader :environment, :team_id

    def base_url
      raw = ENV[ENVIRONMENTS.fetch(@environment)].presence || DEFAULT_URLS.fetch(@environment)
      origin_for(raw)
    end

    def login_url
      "#{base_url}/login"
    end

    def overview_url
      "#{base_url}/overview"
    end

    def credentials
      team = TEAMS.fetch(@team_id)
      password = ENV[team[:password_env]].to_s
      if password.blank?
        raise ConfigurationError, "FAT password is not configured for team #{@team_id}. Set #{team[:password_env]}."
      end

      { email: team[:email], password: password }
    end

    def inspect
      "#<#{self.class.name} environment=#{@environment} team_id=#{@team_id}>"
    end

    private

    def origin_for(raw)
      uri = URI.parse(raw.to_s.strip.sub(%r{/overview/?\z}, ""))
      unless uri.is_a?(URI::HTTP) && uri.host.present?
        raise ConfigurationError, "FAT URL for #{@environment} is not a valid http(s) origin."
      end

      origin = "#{uri.scheme}://#{uri.host}"
      origin += ":#{uri.port}" if uri.port && uri.port != uri.default_port
      origin
    rescue URI::InvalidURIError
      raise ConfigurationError, "FAT URL for #{@environment} is not a valid http(s) origin."
    end
  end
end
