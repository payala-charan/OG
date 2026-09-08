class AutomationSchedule < ApplicationRecord
  has_many :automation_batches, dependent: :destroy

  validates :schedule_type, inclusion: { in: %w[utilization ranking] }
end
