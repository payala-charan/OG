# frozen_string_literal: true

module UtilizationAnalytics
  # Compares an endpoint number with a database number.
  #
  # Display precision is two decimal places, the same precision used by
  # UtilizationAnalyticsHelper#ua_proof_number, #ua_proof_money, and
  # #ua_proof_percent. Both sides are rounded to that precision before an
  # equality check, so a gap smaller than half a cent passes.
  # Record counts compare as whole numbers.
  class Comparator
    def self.compare(displayed:, expected:, kind:)
      if displayed.nil?
        return { "status" => "error", "message" => "Endpoint value is missing." }
      end
      if expected.nil?
        return { "status" => "error", "message" => "DB value is missing." }
      end

      if kind == :count
        shown = displayed.to_i
        calculated = expected.to_i
      else
        shown = displayed.to_f.round(2)
        calculated = expected.to_f.round(2)
      end

      {
        "displayed_value" => kind == :count ? shown : displayed.to_f,
        "db_value" => calculated,
        "status" => shown == calculated ? "passed" : "failed",
        "difference" => kind == :count ? shown - calculated : (shown - calculated).round(2)
      }
    end
  end
end
