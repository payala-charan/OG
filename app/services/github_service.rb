# class GithubService
#   include HTTParty
#   base_uri "https://api.github.com"

#   def initialize(user)
#     @token = user.github_account.access_token
#   end

#   def repositories
#     all_repos = []
    
#     # 1. Fetch explicitly affiliated user repos
#     user_repos = get("/user/repos?per_page=100&affiliation=owner,collaborator,organization_member")
#     all_repos.concat(user_repos) if user_repos.is_a?(Array)

#     # 2. Fetch Organizations the user belongs to and explicitly pull their repos
#     orgs = get("/user/orgs?per_page=100")
#     if orgs.is_a?(Array)
#       orgs.each do |org|
#         org_name = org["login"]
#         next if org_name.blank?

#         org_repos = get("/orgs/#{org_name}/repos?type=all&per_page=100")
#         all_repos.concat(org_repos) if org_repos.is_a?(Array)
#       end
#     end

#     # 3. Deduplicate by unique repository ID to prevent duplicates
#     all_repos.uniq { |repo| repo["id"] }
#   end

#   def pull_requests(owner, repo)
#     get("/repos/#{owner}/#{repo}/pulls?state=all")
#   end

#   def commit_activity(owner, repo)
#     get("/repos/#{owner}/#{repo}/stats/commit_activity")
#   end

#   private

#   def get(path)
#     response = self.class.get(
#       path,
#       headers: {
#         "Authorization" => "token #{@token}",
#         "Accept" => "application/vnd.github+json"
#       }
#     )

#     JSON.parse(response.body)
#   end
# end

require 'httparty'

class GithubService
  include HTTParty

  base_uri "https://api.github.com"

  def initialize(user)
    @token = user.github_account.access_token

    @headers = {
      "Authorization" => "Bearer #{@token}",
      "Accept" => "application/vnd.github+json"
    }
  end


  def repositories
    response = self.class.get(
      "/user/repos",
      headers: @headers
    )

    JSON.parse(response.body)
  end


  def pull_requests(owner, repo)
    response = self.class.get(
      "/repos/#{owner}/#{repo}/pulls?state=all",
      headers: @headers
    )

    JSON.parse(response.body)
  end


  def contributors(owner, repo)
    return [] if owner.blank? || repo.blank?

    response = self.class.get(
      "/repos/#{owner}/#{repo}/contributors",
      headers: @headers
    )

    return [] unless response.success?
    return [] if response.body.blank?

    JSON.parse(response.body)
  end


  # def commit_activity(owner, repo)
  #   response = self.class.get(
  #     "/repos/#{owner}/#{repo}/stats/commit_activity",
  #     headers: @headers
  #   )

  #   JSON.parse(response.body)
  # end
  def commit_activity(owner, repo)
    response = self.class.get(
      "/repos/#{owner}/#{repo}/stats/commit_activity",
      headers: @headers
    )

    return [] unless response.success?
    return [] if response.body.blank?

    data = JSON.parse(response.body)

    # GitHub "processing" case
    return [] if data.is_a?(Hash) && data["message"].present?

    data
  end

  def user_profile_metadata(username)
    query = <<~GRAPHQL
      query($username: String!) {
        user(login: $username) {
          createdAt
        }
      }
    GRAPHQL

    begin
      response = self.class.post(
        "/graphql",
        headers: @headers,
        body: { query: query, variables: { username: username } }.to_json
      )
      
      return nil unless response.success?
      JSON.parse(response.body).dig("data", "user")
    rescue StandardError => e
      Rails.logger.warn("GraphQL Fetch Failed: #{e.message}")
      nil
    end
  end

  def user_contributions_heatmap(username, from_date, to_date)
    query = <<~GRAPHQL
      query($username: String!, $from: DateTime!, $to: DateTime!) {
        user(login: $username) {
          contributionsCollection(from: $from, to: $to) {
            contributionCalendar {
              totalContributions
              weeks {
                contributionDays {
                  contributionCount
                  date
                  color
                }
              }
            }
          }
        }
      }
    GRAPHQL

    begin
      response = self.class.post(
        "/graphql",
        headers: @headers,
        body: { query: query, variables: { username: username, from: from_date, to: to_date } }.to_json
      )

      return nil unless response.success?
      JSON.parse(response.body).dig("data", "user", "contributionsCollection", "contributionCalendar")
    rescue StandardError => e
      Rails.logger.warn("GraphQL Fetch Failed: #{e.message}")
      nil
    end
  end
end