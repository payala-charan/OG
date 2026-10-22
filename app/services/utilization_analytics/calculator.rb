# frozen_string_literal: true

module UtilizationAnalytics
  # Independent database calculations for Utilization Analytics validation.
  #
  # Quarterly periods filter UtilizationReport and PurchaseHistory by
  # accounting_period_id. Monthly periods filter those tables by data_month.
  # NewBiosimilarPrice billing_unit_per_package_size always uses
  # accounting_period_id 7, for every quarter and every month.
  # An NDC shorter than 11 characters is matched as 11 characters with
  # leading zeroes, which is how that sheet stores the code.
  #
  # Product cost per unit is the weighted ratio
  # Σ(invoice_price × quantity) / Σ(billing_unit_per_package_size × quantity).
  # Lines with a zero invoice price or quantity are left out, matching the
  # calculation proof. A purchase line with no package size is an error.
  class Calculator
    WHOLESALER_TYPE = "340B"
    NDC_LENGTH = 11
    OUTPATIENT_CLASSES = [ "Outpatient", "Emergency" ].freeze
    Measurement = Struct.new(
      :units,
      :reimbursement,
      :cost_per_unit,
      :product_cost,
      :total_margin,
      :margin_per_unit,
      :margin_percent,
      :inpatient_count,
      :purchase_line_count,
      :cost_error,
      :margin_per_unit_error,
      :margin_percent_error,
      keyword_init: true
    )
    Failure = Struct.new(:message)
    Cost = Struct.new(:value, :lines, keyword_init: true)

    def initialize(team_id:, group: nil, charge_class: nil, hospital_names: [], payor_names: [])
      @team_id = team_id.to_s
      @group = group.to_s.strip
      @charge_class = charge_class.to_s
      @hospital_names = Array(hospital_names).map(&:to_s).reject(&:blank?)
      @payor_names = Array(payor_names).map(&:to_s).reject(&:blank?)
    end

    def measure(brand_name, period)
      units = utilization_value(period, table_charge_classes, brand_name, :units)
      reimbursement = utilization_value(period, table_charge_classes, brand_name, :reimbursement)
      inpatient_count = utilization_value(period, [ "Inpatient" ], brand_name, :count)
      cost = product_cost(brand_name, period)

      if cost.is_a?(Failure)
        return Measurement.new(
          units: units,
          reimbursement: reimbursement,
          inpatient_count: inpatient_count,
          cost_error: cost.message,
          margin_per_unit_error: units.zero? ? zero_units_message : cost.message,
          margin_percent_error: cost.message
        )
      end

      product_cost_total = cost.value * units
      margin = reimbursement - product_cost_total
      per_unit_error = units.zero? ? zero_units_message : nil
      percent_error = product_cost_total.zero? ? zero_cost_message : nil

      Measurement.new(
        units: units,
        reimbursement: reimbursement,
        cost_per_unit: cost.value,
        product_cost: product_cost_total,
        total_margin: margin,
        margin_per_unit: per_unit_error ? nil : margin / units,
        margin_percent: percent_error ? nil : (margin / product_cost_total * 100),
        inpatient_count: inpatient_count,
        purchase_line_count: cost.lines,
        margin_per_unit_error: per_unit_error,
        margin_percent_error: percent_error
      )
    end

    private

    attr_reader :team_id, :group, :charge_class, :hospital_names, :payor_names

    def table_charge_classes
      charge_class.casecmp("inpatient").zero? ? [ "Inpatient" ] : OUTPATIENT_CLASSES
    end

    def utilization_value(period, charge_classes, brand_name, field)
      bucket = utilization_totals(period, charge_classes)[brand_name.to_s.upcase]
      return 0.0 if bucket.nil? && field != :count
      return 0 if bucket.nil?

      bucket[field]
    end

    def utilization_totals(period, charge_classes)
      @utilization_totals ||= {}
      @utilization_totals[[ period.cache_key, charge_classes ]] ||= aggregate_utilization(period, charge_classes)
    end

    def aggregate_utilization(period, charge_classes)
      rows = utilization_scope(period, charge_classes).pluck(
        "utilization_reports.id",
        Arel.sql("UPPER(ndc_codes.brand_name)"),
        "utilization_reports.cms_total_units",
        "utilization_reports.actual_reimbursement"
      )
      totals = Hash.new { |hash, key| hash[key] = { units: 0.0, reimbursement: 0.0, count: 0 } }
      rows.uniq { |id, brand, _, _| [ id, brand ] }.each do |_, brand, units, reimbursement|
        bucket = totals[brand.to_s]
        bucket[:units] += units.to_f
        bucket[:reimbursement] += reimbursement.to_f
        bucket[:count] += 1
      end
      totals
    end

    def utilization_scope(period, charge_classes)
      scope = Tables.utilization_reports.where(team_id: team_id, category: nil, charge_class: charge_classes)
      scope = period.monthly? ? scope.where(data_month: period.data_month) : scope.where(accounting_period_id: period.accounting_period_id)
      scope = scope.where("UPPER(utilization_reports.generic_name_group) = ?", group.upcase) if group.present?
      scope = scope.where(hospital_name: hospital_names) if hospital_names.any?
      scope = scope.where(payor_exists_sql, payor_names.map(&:upcase), payor_names.map(&:upcase)) if payor_names.any?
      scope.joins("INNER JOIN ndc_codes ON ndc_codes.utilization_report_id = utilization_reports.id")
    end

    def payor_exists_sql
      "EXISTS (SELECT 1 FROM primary_payors WHERE primary_payors.utilization_report_id = utilization_reports.id " \
        "AND (UPPER(primary_payors.primary_payor_name) IN (?) OR UPPER(primary_payors.benefit_plan_name) IN (?)))"
    end

    def product_cost(brand_name, period)
      lines = purchase_lines(period)[brand_name.to_s.upcase] || []
      candidates = lines.select { |price, qty, _| price.to_f.nonzero? && qty.to_f.nonzero? }
      if candidates.empty?
        return Failure.new("Unable to validate Product Cost Per Unit because no purchase lines were found.")
      end

      price_period_id = period.price_accounting_period_id
      load_prices(candidates.map(&:last), price_period_id)
      usable = []
      candidates.each do |price, qty, ndc|
        package_size = package_size_for(ndc, price_period_id)
        return package_size if package_size.is_a?(Failure)

        usable << [ price.to_f, qty.to_f, package_size ]
      end

      invoice_total = usable.sum { |price, qty, _| price * qty }
      billing_total = usable.sum { |_, qty, package_size| package_size * qty }
      if billing_total.zero?
        return Failure.new("Unable to validate Product Cost Per Unit because total billing units are zero.")
      end

      Cost.new(value: invoice_total / billing_total, lines: usable.size)
    end

    def purchase_lines(period)
      @purchase_lines ||= {}
      @purchase_lines[period.cache_key] ||= begin
        scope = Tables.purchase_histories.where(team_id: team_id, wholesaler_purchase_type: WHOLESALER_TYPE)
        scope = period.monthly? ? scope.where(data_month: period.data_month) : scope.where(accounting_period_id: period.accounting_period_id)
        scope = scope.where("UPPER(purchase_histories.generic_name_group) = ?", group.upcase) if group.present?
        scope.pluck(:brand_name, :invoice_price, :total_quantity_ordered, :ndc_product_id)
             .group_by { |brand, _, _, _| brand.to_s.upcase }
             .transform_values { |rows| rows.map { |_, price, qty, ndc| [ price, qty, ndc ] } }
      end
    end

    def load_prices(ndc_codes, period_id)
      @ndc_prices ||= {}
      @alternate_prices ||= {}
      @prices_loaded ||= {}
      codes = ndc_codes.map { |code| normalize_ndc(code) }.reject(&:blank?).uniq
      missing = codes.reject { |code| @prices_loaded[[ period_id, code ]] }
      return if missing.empty?

      fetch_prices(missing, period_id, :ndc_code).each do |code, values|
        @ndc_prices[[ period_id, code ]] = values
      end
      unresolved = missing.select { |code| Array(@ndc_prices[[ period_id, code ]]).compact.empty? }
      fetch_prices(unresolved, period_id, :alternate_ndc_code).each do |code, values|
        @alternate_prices[[ period_id, code ]] = values
      end
      missing.each { |code| @prices_loaded[[ period_id, code ]] = true }
    end

    def fetch_prices(codes, period_id, column)
      grouped = Hash.new { |hash, key| hash[key] = [] }
      return grouped if codes.empty?

      stored = Hash.new { |hash, key| hash[key] = [] }
      queried = codes.flat_map { |code| lookup_variants(code) }.uniq
      Tables.new_biosimilar_prices
            .where(team_id: team_id, accounting_period_id: period_id, column => queried)
            .pluck(column, :billing_unit_per_package_size)
            .each { |code, package_size| stored[normalize_ndc(code)] << package_size }

      codes.each do |code|
        lookup_variants(code).each do |variant|
          values = stored[variant]
          next if values.compact.empty?

          grouped[code] = values
          break
        end
      end
      grouped
    end

    def package_size_for(ndc, period_id)
      code = normalize_ndc(ndc)
      values = Array(@ndc_prices[[ period_id, code ]]).compact.uniq
      values = Array(@alternate_prices[[ period_id, code ]]).compact.uniq if values.empty?
      if values.empty?
        Failure.new("Unable to validate Product Cost Per Unit because no billing unit/package size was found for NDC #{ndc}.")
      elsif values.size > 1
        Failure.new("Unable to validate Product Cost Per Unit because multiple billing unit/package sizes were found for NDC #{ndc}.")
      else
        values.first.to_f
      end
    end

    def normalize_ndc(code)
      code.to_s.strip
    end

    # The 11-character form is tried first. The original code is the fallback
    # when the sheet has no zero-padded row.
    def lookup_variants(code)
      normalized = normalize_ndc(code)
      padded = normalized.length < NDC_LENGTH ? normalized.rjust(NDC_LENGTH, "0") : normalized
      [ padded, normalized ].uniq
    end

    def zero_units_message
      "Unable to validate Margin Per Unit because CMS total units are zero."
    end

    def zero_cost_message
      "Unable to validate Margin % of Cost because total product cost is zero."
    end
  end
end
