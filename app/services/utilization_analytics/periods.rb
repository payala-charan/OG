# frozen_string_literal: true

module UtilizationAnalytics
  # Maps a selected quarter label to accounting_period_id.
  # The ids match QuarterStatusesController and are only a fallback for when
  # the accounting_periods table has no matching name.
  class Periods
    class UnknownQuarter < StandardError; end

    QUARTER_IDS = {
      "Q4 2024" => 1,
      "Q1 2025" => 2,
      "Q2 2025" => 3,
      "Q3 2025" => 4,
      "Q4 2025" => 5,
      "Q1 2026" => 6,
      "Q2 2026" => 7,
      "Q3 2026" => 8
    }.freeze

    # billing_unit_per_package_size always comes from this biosimilar sheet,
    # for every quarter and every month.
    PRICE_PERIOD_ID = 7

    def self.accounting_period_id(quarter_name)
      label = compact(quarter_name)
      from_table = lookup_table(quarter_name, label)
      return from_table if from_table

      QUARTER_IDS[label] || raise(UnknownQuarter, "No accounting period for #{quarter_name}.")
    end

    def self.compact(name)
      text = name.to_s.strip.gsub(/\s+/, " ")
      match = text.match(/\Aquarter\s+(\d)\s+(\d{4})\z/i)
      return "Q#{match[1]} #{match[2]}" if match

      text.sub(/\Aquarter\b/i, "Q")
    end

    def self.lookup_table(original, label)
      return unless defined?(AccountingPeriod)
      return unless AccountingPeriod.respond_to?(:table_exists?) && AccountingPeriod.table_exists?

      names = [ original.to_s.strip, label, label.sub(/\AQ(\d) (\d{4})\z/, 'Quarter \1 \2') ]
      AccountingPeriod.where("LOWER(name) IN (?)", names.map { |item| item.to_s.downcase }).pick(:id)
    rescue ActiveRecord::ActiveRecordError
      nil
    end
    private_class_method :lookup_table
  end
end
