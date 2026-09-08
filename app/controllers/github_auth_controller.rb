class GithubAuthController < ApplicationController
  def callback
    auth = request.env['omniauth.auth']

    account = current_user.build_github_account(
      username: auth.info.nickname,
      access_token: auth.credentials.token
    )

    account.save

    redirect_to github_dashboard_path
  end
end