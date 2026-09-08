class VoiceQueryLog < ApplicationRecord

  # Always keep last 20 logs only
  after_create :trim_logs

  private

  def trim_logs
    excess = VoiceQueryLog.order(created_at: :desc).offset(20)
    excess.destroy_all if excess.any?
  end
end
