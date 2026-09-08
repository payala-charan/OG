class GithubAnalyticsService
  def initialize(pull_requests)
    @pull_requests = pull_requests
  end

  def total_prs
    @pull_requests.count
  end

  def open_prs
    @pull_requests.count { |pr| pr.state == "open" }
  end

  def closed_prs
    @pull_requests.count { |pr| pr.state == "closed" }
  end

  def merged_prs
    @pull_requests.count { |pr| pr.merged }
  end

  def contributions_by_author
    grouped = @pull_requests.group_by(&:author)

    grouped.transform_values(&:count)
  end

  def daily_contributions(author)
    @pull_requests
      .select { |pr| pr.author == author }
      .group_by { |pr| pr.created_at.to_date }
      .transform_values(&:count)
  end

  def monthly_contributions(author)
    @pull_requests
      .select { |pr| pr.author == author }
      .group_by { |pr| pr.created_at.strftime("%Y-%m") }
      .transform_values(&:count)
  end

  def yearly_contributions(author)
    @pull_requests
      .select { |pr| pr.author == author }
      .group_by { |pr| pr.created_at.year }
      .transform_values(&:count)
  end

  def combined_daily_contributions
    @pull_requests.group_by(&:author).transform_values do |prs|
      prs.group_by { |pr| pr.created_at.to_date }.transform_values(&:count)
    end
  end

  def combined_monthly_contributions
    @pull_requests.group_by(&:author).transform_values do |prs|
      prs.group_by { |pr| pr.created_at.strftime("%Y-%m") }.transform_values(&:count)
    end
  end

  def combined_yearly_contributions
    @pull_requests.group_by(&:author).transform_values do |prs|
      prs.group_by { |pr| pr.created_at.year }.transform_values(&:count)
    end
  end
end