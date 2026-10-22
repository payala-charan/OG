# frozen_string_literal: true

module UtilizationAnalytics
  class Period
    attr_reader :kind, :role, :label, :accounting_period_id, :data_month

    def self.quarter(role:, label:, accounting_period_id:)
      new(kind: "quarter", role: role, label: label, accounting_period_id: accounting_period_id)
    end

    def self.month(role:, label:, data_month:)
      new(kind: "month", role: role, label: label, data_month: data_month)
    end

    def initialize(kind:, role:, label:, accounting_period_id: nil, data_month: nil)
      @kind = kind
      @role = role
      @label = label.to_s
      @accounting_period_id = accounting_period_id
      @data_month = data_month
    end

    def monthly?
      kind == "month"
    end

    def price_accounting_period_id
      Periods::PRICE_PERIOD_ID
    end

    def cache_key
      monthly? ? "month:#{data_month}" : "quarter:#{accounting_period_id}"
    end
  end
end
