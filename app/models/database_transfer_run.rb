# frozen_string_literal: true

# Audit log for FAT → OG transfers. Written outside the transfer transaction,
# so a failed or rolled-back transfer still leaves its record.
class DatabaseTransferRun < ApplicationRecord
  # A worker that died mid-run leaves "running" behind. PostgreSQL has already
  # rolled its transaction back, so after this long the run no longer blocks new ones.
  STALE_AFTER = 6.hours

  belongs_to :user, optional: true

  enum :status, {
    pending: 0,
    running: 1,
    succeeded: 2,
    failed: 3,
    rolled_back: 4
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: [ :pending, :running ]).where(created_at: STALE_AFTER.ago..) }

  def finished?
    succeeded? || failed? || rolled_back?
  end

  # A committed transfer can be dropped. A rehearsal never kept its tables.
  def rollbackable?
    succeeded? && !rehearsal? && planned_tables.present?
  end

  def outcome_label
    return status.humanize unless succeeded?

    rehearsal? ? "Rehearsal passed (rolled back)" : "Committed"
  end

  def table_summaries
    Array(summary["tables"])
  end

  def total_rows
    table_summaries.sum { |table| table["rows"].to_i }
  end
end
