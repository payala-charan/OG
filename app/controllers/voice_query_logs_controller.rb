class VoiceQueryLogsController < ApplicationController
  def index
    @logs = VoiceQueryLog.order(created_at: :desc).limit(20)
  end
end
