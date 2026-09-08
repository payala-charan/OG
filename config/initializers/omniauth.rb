OmniAuth.config.allowed_request_methods = [ :post ]
Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
    ENV["GOOGLE_CLIENT_ID"],
    ENV["GOOGLE_CLIENT_SECRET"],
    {
      scope: [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/calendar",
        "https://www.googleapis.com/auth/gmail.readonly"
      ].join(" "),
      access_type: "offline",
      prompt: "consent",
      response_type: "code"
    }


  provider :github,
    ENV["GITHUB_CLIENT_ID"],
    ENV["GITHUB_CLIENT_SECRET"],
    scope: "repo,read:user,user:email,read:org,read:discussion"
end

