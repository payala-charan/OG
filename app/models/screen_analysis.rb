class ScreenAnalysis < ApplicationRecord
  has_one_attached :image

  validates :title, presence: true
  validates :summary, presence: true
  validates :image, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
