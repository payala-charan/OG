class GithubController < ApplicationController
  before_action :require_login

  def index
    # Just the connection gateway
  end

  def callback
    auth = request.env["omniauth.auth"]

    account = current_user.github_account || current_user.build_github_account

    account.update(
      username: auth.info.nickname,
      access_token: auth.credentials.token
    )

    redirect_to github_dashboard_path
  end

  def dashboard
    @github_account = current_user.github_account
    return redirect_to github_path if @github_account.nil?

    @repositories = @github_account.github_repositories

    if @repositories.empty?
      fetch_and_store_github_data
      @repositories = @github_account.github_repositories
    end

    @selected_repo = params[:repo_id]

    if @selected_repo.present?
      @pull_requests = GithubPullRequest.where(github_repository_id: @selected_repo)
    else
      repository_ids = @repositories.pluck(:id)
      @pull_requests = GithubPullRequest.where(github_repository_id: repository_ids)
    end

    @total_prs = @pull_requests.count
    @open_prs = @pull_requests.where(state: "open").count
    @closed_prs = @pull_requests.where(state: "closed").count
    @merged_prs = @pull_requests.where(merged: true).count
    analytics = GithubAnalyticsService.new(@pull_requests)
    
    @yearly_pr_contributions = @pull_requests
      .where(created_at: Date.current.beginning_of_year..Date.current.end_of_year)
      .group(:author)
      .count

    @monthly_pr_contributions = @pull_requests
      .where(created_at: Date.current.beginning_of_month..Date.current.end_of_month)
      .group(:author)
      .count

    @total_yearly_prs = @yearly_pr_contributions.values.sum
    @total_monthly_prs = @monthly_pr_contributions.values.sum

    # Commit contributions are now loaded from stored DB contributions, not calling GitHub API on each dashboard visit.
    @commit_contributions = GithubContribution
      .joins(:github_repository)
      .where(github_repositories: { github_account_id: @github_account.id })
      .group(:author)
      .sum(:commits)

    @total_commit_contributions = @commit_contributions.values.sum

    # Heatmap using GitHub GraphQL real-time exact data
    graph_username = params[:author].presence || @github_account.username
    selected_year = params[:year].present? ? params[:year].to_i : Date.current.year
    
    github_service = GithubService.new(current_user)
    profile_meta = github_service.user_profile_metadata(graph_username)
    
    start_year = profile_meta ? Time.parse(profile_meta["createdAt"]).year : Date.current.year
    @available_years = (start_year..Date.current.year).to_a.reverse

    # ISO-8601 Boundaries
    from_date = Time.new(selected_year, 1, 1).utc.iso8601
    to_date = Time.new(selected_year, 12, 31, 23, 59, 59).utc.iso8601

    heatmap_result = github_service.user_contributions_heatmap(graph_username, from_date, to_date)

    @heatmap_data = {
      username: graph_username,
      year: selected_year,
      total: heatmap_result ? heatmap_result["totalContributions"] : 0,
      weeks: heatmap_result ? heatmap_result["weeks"] : []
    }


    @author_contributions = analytics.contributions_by_author

    # Aggregate global combinations for Chart.js rendering (DB-driven)
    @combined_daily_data = analytics.combined_daily_contributions
    @combined_monthly_data = analytics.combined_monthly_contributions
    @combined_yearly_data = analytics.combined_yearly_contributions

    # Single Author overrides using real-time GraphQL
    if @heatmap_data[:weeks].present?
      daily_graph = {}
      monthly_graph = Hash.new(0)
      
      @heatmap_data[:weeks].each do |week|
        week["contributionDays"].each do |day|
          date_str = day["date"]
          count = day["contributionCount"]
          
          daily_graph[date_str] = count
          monthly_graph[date_str[0, 7]] += count
        end
      end
      
      @daily_data = daily_graph.to_a.last(30).to_h
      @monthly_data = monthly_graph
      @yearly_data = { selected_year.to_s => @heatmap_data[:total] }
    else
      @daily_data = analytics.daily_contributions(params[:author])
      @monthly_data = analytics.monthly_contributions(params[:author])
      @yearly_data = analytics.yearly_contributions(params[:author])
    end
  end

  def refresh
    account = current_user.github_account
    return redirect_to github_dashboard_path if account.nil?

    account.github_repositories.destroy_all
    fetch_and_store_github_data

    redirect_to github_dashboard_path
  end

  private

  def fetch_and_store_github_data
    github_service = GithubService.new(current_user)
    repos = github_service.repositories

    repos.each do |repo|
      repository = current_user.github_account.github_repositories.create(
        name: repo["name"],
        owner: repo["owner"]["login"]
      )

      # 🔹 Pull Requests
      pull_requests = github_service.pull_requests(repo["owner"]["login"], repo["name"])
      if pull_requests.is_a?(Array)
        pull_requests.each do |pr|
          repository.github_pull_requests.create(
            pr_number: pr["number"],
            title: pr["title"],
            author: pr.dig("user", "login"),
            state: pr["state"],
            merged: pr["merged_at"].present?,
            merged_by: pr.dig("merged_by", "login"),
            created_at: pr["created_at"],
            closed_at: pr["closed_at"]
          )
        end
      end

      # 🔹 Commit Activity
      commit_data = github_service.commit_activity(repo["owner"]["login"], repo["name"])
      next if commit_data.blank? || commit_data.is_a?(Hash)

      commit_data.each do |week|
        week["days"].each_with_index do |count, index|
          date = Time.at(week["week"]) + index.days
          repository.github_contributions.create(
            author: "all",
            date: date,
            commits: count
          )
        end
      end
    end
  end
end