class FeaturesController < ApplicationController
  before_action :require_login
  def index
  end

  def run_automation
    # Spawn the process in the background, detach it so it doesn't block the request, and pass the WEB_TRIGGER env variable
    pid = Process.spawn({ "WEB_TRIGGER" => "true" }, "bundle exec ruby automation/runner.rb")
    Process.detach(pid)

    redirect_to features_path, notice: "Browser automation started! The browser should open shortly."
  end
end
