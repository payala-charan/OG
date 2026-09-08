# frozen_string_literal: true
class UtilizationReport < ApplicationRecord
  include ActionView::Helpers::NumberHelper
  require 'axlsx'
  # has_paper_trail

  belongs_to :user, foreign_key: :team_id, primary_key: :team_id, optional: true
  has_many :utilization_conversion_histories, foreign_key: :team_id, primary_key: :team_id
  has_one :invoice_conversion, dependent: :destroy
  has_one :utilization_order, dependent: :destroy
  has_one :primary_payor, dependent: :destroy
  has_one :ndc_code_record, class_name: "NdcCode", dependent: :destroy
  belongs_to :accounting_period
  belongs_to :reimbursement
  has_many :purchase_histories, through: :accounting_period
  after_commit :enqueue_conversion_recalculation,
               on: :update,
               if: :cost_changed?

  accepts_nested_attributes_for :utilization_order, allow_destroy: true
  accepts_nested_attributes_for :ndc_code_record, allow_destroy: true
  accepts_nested_attributes_for :primary_payor, allow_destroy: true

  before_save :calculate_margins
  before_validation :preserve_nil_for_category

  BATCH_SIZE = 500

  scope :distinct_generic_name_groups, -> {
    select(:generic_name_group).distinct.pluck(:generic_name_group)
  }

  scope :distinct_hospital_names, -> {
    select(:hospital_name).distinct.pluck(:hospital_name)
  }

  scope :by_health_system_and_hospitals, ->(hospitals) {
    where(hospital_name: hospitals)
  }

  scope :by_generic_group, ->(group) {
    where(generic_name_group: group)
  }

  scope :by_group, ->(group) {
    where(generic_name_group: group)
  }

  scope :by_date_range, ->(start_date, end_date) {
    where(administration_instant: start_date..end_date) if start_date.present? && end_date.present?
  }

  def biosimilars
    BiosimilarPrice.where(team_id: team_id, accounting_period_id: accounting_period_id, status: nil)
                   .where(generic_name_group: generic_name_group&.upcase)
  end

  def generic_group_purchase_histories
    PurchaseHistory.where(team_id: team_id, accounting_period_id: accounting_period_id)
                   .where(generic_name_group: generic_name_group&.upcase)
  end

  def self.open_spreadsheet(file)
    filename = file.respond_to?(:original_filename) ? file.original_filename : file.path
    extension = File.extname(filename)

    case extension
    when '.csv'  then Roo::CSV.new(file.path)
    when '.xls'  then Roo::Excel.new(file.path)
    when '.xlsx' then Roo::Excelx.new(file.path)
    else
      raise "Unknown file type: #{filename}"
    end
  end

  def self.process_file(parsed_file, team_id: nil, source_key: nil)
    batch = []
    batch_size = 1000
    total_rows = 0
    all_sheets = parsed_file.sheets

    @headers = {}
    @current_team_id = team_id
    faulty_ndc_map = FaultyNdcCode.all.index_by(&:corrupted_ndc_code)

    all_sheets.each do |sheet|
      parsed_file.default_sheet = sheet

      parsed_file.each_with_index do |row, i|
        if i.zero?
          @headers = build_headers(row)
        else
          row_hash = row_to_hash(row)
          row_hash["team_id"] = team_id.to_s if team_id.present?
          batch << row_hash
        end

        if batch.size >= batch_size
          enqueue_batch(batch, faulty_ndc_map)
          batch = []
        end

        total_rows = i
      end
    end

    enqueue_batch(batch, faulty_ndc_map)
    total_rows
  end

  def enqueue_conversion_recalculation
    all_matched_ndc_codes = UtilizationReport.where(accounting_period_id: self.accounting_period_id).joins(:ndc_code_record).where({ ndc_code_record: { ndc_code: self.ndc_code_record&.ndc_code}}).pluck(:utilization_report_id)
    UtilizationReport.where(id: all_matched_ndc_codes).update_all(price_without_cost_dist_minus: self.price_without_cost_dist_minus)
    all_matched_ndc_codes.each do |id|
      UtilizationReportConversionsBatchJob.perform_later(id, 100, self.generic_name_group.capitalize, self.accounting_period_id, "default_version")
    end
    ndc_code = self.ndc_code_record&.ndc_code
    return if ndc_code.blank?
    bp = BiosimilarPrice.find_by(ndc_code: ndc_code, accounting_period_id: accounting_period_id) ||
     BiosimilarPrice.find_by(alternate_ndc_code: ndc_code, accounting_period_id: accounting_period_id) ||
     BiosimilarPrice.find_by(other_ndc_codes: ndc_code, accounting_period_id: accounting_period_id)
    return unless bp
    bp.skip_recalculation_callback = true
    if self.charge_class.to_s.downcase == "inpatient"
      bp.update(gpo_cost: self.price_without_cost_dist_minus)
      cms_reimbursement = BiosimilarPrice.where(accounting_period_id: bp.accounting_period_id, ndc_code: bp.ndc_code).pluck(:cms_reimbursement_per_package).first
      cms_margin_gpo_cost = cms_reimbursement - bp.gpo_cost
      gpo_percent_margin = (cms_margin_gpo_cost / bp.gpo_cost) * 100
      bp.update_columns(
        cms_margin_gpo_cost: cms_margin_gpo_cost.round(2),
        gpo_percent_margin: gpo_percent_margin.round(2)
      )
    else
      bp.update(cost_three_forty_b: self.price_without_cost_dist_minus)
      cms_margin_cost_per_unit_340b = bp.cost_three_forty_b / bp.billing_unit_per_package_size
      cms_margin_340b_cost = bp.cms_reimbursement_per_package - bp.cost_three_forty_b
      cms_percent_margin = (cms_margin_340b_cost / bp.cost_three_forty_b) * 100
      bp.update_columns(
        cost_per_unit_three_forty_b: cms_margin_cost_per_unit_340b.round(2),
        cms_margin_three_forty_b_cost: cms_margin_340b_cost.round(2),
        cms_percent_margin: cms_percent_margin.round(2)
      )
    end
  end

  def self.row_to_hash(row)
    Hash[@headers.keys.zip(row)]
  end

  def self.build_headers(row)
    headers = {}
    normalized_headers = row.map { |x| normalize_header(x) }
    normalized_headers.each_with_index { |header, index| headers[header] = index }

    missing_headers = expected_headers.map(&:downcase) - headers.keys.map(&:downcase)
    raise "Missing required header entry '#{missing_headers[0]}'" unless missing_headers.empty?

    headers
  end

  def self.normalize_header(header)
    header = header.to_s.downcase.gsub(/(\d+)/) { |num| number_to_word(num.to_i) }
    header.scan(/[a-z0-9]+/).join("_")
  end

  def self.number_to_word(number)
    words = %w[zero one two three four five six seven eight nine ten]
    words[number] || number.to_s
  end

  def self.expected_headers
    # %w[har csn mrn patient_age order_date_time ordering_mode order_status order_id order_name
    #   generic_name order_description administration_instant mar_action quantity qty_unit_name strength
    #   pack_desc ndc_code package_size hcpcs_code charge_type charge_class financial_class primary_dx diagnosis_two
    #   diagnosis_three diagnosis_four primary_payor_name benefit_plan_name prescribing_provider_nm order_department
    #   dispense_department administration_department hospital_name generic_name_group charge medication_id admin_amount
    #   admin_unit package_unit hospital_group data_month quarter reimbursement health_system accounting_period_id]

      %w[ har csn mrn patient_age order_status charge order_date_time order_id order_name order_description
      generic_name medication_id admin_amount admin_unit administration_instant mar_action charge_type strength
      quantity qty_unit_name pack_desc package_size package_unit ndc_code hcpcs_code charge_class
      financial_class primary_dx diagnosis_two diagnosis_three diagnosis_four primary_payor_name benefit_plan_name prescribing_provider_nm
      dispense_department administration_department hospital_name generic_name_group accounting_period_id reimbursement_id data_month team_id]
  end

  def self.enqueue_batch(batch, _faulty_ndc_map = nil)
    UtilizationReportImportJob.perform_later(batch)
  end

  def self.update_insurances_cms_asp
    invoices = UtilizationReport.where(accounting_period_id: 5, team_id: "198")

    invoices.find_each do |record|
      benefit_plan_name = record&.primary_payor&.benefit_plan_name
      next unless record.hospital_name && benefit_plan_name

      insurance_factor = case benefit_plan_name
                        when /AETNA/ then 208.0
                        when /ANTHEM/ then 180.0
                        when /CIGNA/ then 179.2
                        when /SENTARA/ then 148.0
                        when /UNITED HEALTHCARE/ then 200.0
                        end

      record.update(insurance_factor: insurance_factor) if insurance_factor
    end
  end

  def self.update_insurances_cms_asp
    invoices = UtilizationReport.where(team_id: "209", created_at: Time.zone.today.all_day)

    invoices.find_each do |record|
      benefit_plan_name = record&.primary_payor&.benefit_plan_name
      next unless benefit_plan_name

      insurance_factor = case benefit_plan_name
                        when /PACIFICSOURCE NAVIGATOR SMART GROUP/ then 105.4
                        when /PACIFICSOURCE EMPLOYEES NAVIGATOR/ then 105.4
                        when /PACIFICSOURCE NAVIGATOR SMART INDIVIDUAL/ then 105.4
                        when /BCBS PREFERRED PROVIDER/ then 190.0
                        when /BCBS SCHS/ then 190.0
                        when /BCBS FEDERAL EMPLOYEE/ then 190.0
                        when /BCBS VALUEPPO/ then 190.0
                        when /BCBS PARTICIPATING/ then 190.0
                        when /PSCS CENTRAL OREGON/ then 86.0
                        when /CASCADE HEALTH ALLIANCE CCO OH/ then 86.0
                        when /PSCS GORGE/ then 86.0
                        when /EASTERN OREGON CCO OHP/ then 86.0
                        when /HEALTH SHARE OHSU/ then 86.0
                        when /PSCS BRIDGE HEALTHIER OREGON/ then 92.0
                        end

      record.update(insurance_factor: insurance_factor) if insurance_factor
    end
  end

  def self.search(query)
    if query.present?
      where('generic_name_group ILIKE :search',
            search: "%#{query.strip}%")
    else
      all
    end
  end

  def self.update_price_from_purchase_history
    utilization_report_ids = UtilizationReport.where(accounting_period_id: 2, category: nil).pluck(:id)
    utilization_report_ids.each do |utilization_report_id|
      PriceUpdateJob.perform_later(utilization_report_id)
      sleep 0.2
    end
  end

  def self.utilization_total_units
    groups = [ ["Pegfilgrastim"], ["Bevacizumab"], ["Filgrastim"], ["Infliximab"], ["Trastuzumab"], ["Rituximab"] ]
    groups.each do |group|
      UtilizationReport.where(generic_name_group: group, accounting_period_id: 3).each do |record|
          quantity = record.quantity.to_d
          package_size = record.ndc_code_record.package_size.to_d
          strength = record.ndc_code_record.strength[/\d+(\.\d+)?/].to_d rescue 1

          units = if record.charge_type == "Charge for Waste" && (record.generic_name_group == "Infliximab" || record.generic_name_group == "Trastuzumab")
            if record.generic_name_group == "Infliximab"
              (quantity / 100) / package_size
            elsif record.generic_name_group == "Trastuzumab"
              ((quantity * 10) / strength) / package_size
            end
          else
            package_size.zero? ? 0 : quantity / package_size
          end

        record.update(total_units: units.to_f)
      end
    end
  end

  def self.calculate_total_cms_units
    UtilizationReport.where(accounting_period_id: 4, category: nil, team_id: "209")
                     .joins(:ndc_code_record)
                     .find_each do |ur|
        ndc_code = ur.ndc_code_record.ndc_code
        biosimilar = ur.biosimilars.where(ndc_code: ndc_code, status: nil).first ||
                     ur.biosimilars.where(alternate_ndc_code: ndc_code, status: nil).first ||
                     ur.biosimilars.where(other_ndc_codes: ndc_code, status: nil).first

        next if biosimilar.blank?
        next if biosimilar.billing_unit_per_package_size.blank?

        cms_total_units = biosimilar.billing_unit_per_package_size.to_f.round(2) *
                          ur.total_units.to_f.round(2)
        ur.update(cms_total_units: cms_total_units.round(2))
      end
  end

  def self.utilization_report_insurance_payment
    AccountingPeriod.find_each do |quarter|
      quarter.utilization_reports.find_each do |report|

        UtilizationReport.where(accounting_period_id: 5, category: nil).pluck(:id).each do |report_id|
        UtilizationReportInsuranceJob.perform_now(report_id)
        sleep 0.2
        end
      end
    end
  end

  def self.utilization_report_actual_insurance_payment
    UtilizationReport.where(accounting_period_id: 1).pluck(:id).each do |report_id|
      ActualInsuranceUpdateJob.perform_later(report_id)
      sleep 0.3
    end
  end

  def self.invoice_default_conversions_to_high_margin
   invoice_ids = UtilizationReport.where(accounting_period_id: 3).pluck(:id)

    invoice_ids.each do |invoice_id|
      UtilizationReportConversionsBatchJob.perform_later([invoice_id], 100)
    end
  end

  def update_total_margin_and_percent_margin
    UtilizationReport.where(accounting_period_id: 3).each do |detail|
     percent_margin = ((detail.insurance_payment_per_dose.round(2) - (detail.price_without_cost_dist_minus.to_f.round(2) * (detail.total_units.round(2))).to_f) / (detail.price_without_cost_dist_minus.to_f.round(2) * (detail.total_units.round(2))).to_f) * 100.0
    detail.update(percent_margin: percent_margin)
    end

    UtilizationReport.where(accounting_period_id: 3).each do |detail|
     total_margin =  detail.insurance_payment_per_dose.round(2) - (detail.price_without_cost_dist_minus.to_f.round(2) * (detail.total_units.round(2)))
     detail.update(total_margin: total_margin)
    end
  end

  def self.fetch_cms_reimbursement_data(user, params)
    invoice_details = fetch_invoice_details(user, params)

    if params[:percentage].present? && params[:product].present?
      conversion_data = calculate_conversion_data(user, invoice_details, params)
      return [invoice_details, conversion_data]
    end

    [invoice_details, nil]
  end

  def self.fetch_invoice_details(user, params)
    start_date = Date.new(2024, 1, 1)
    end_date = Date.new(2024, 12, 31)

    purchase_type_mapping = {
      'GPO' => ['Premier 503B', 'Premier Contract', 'Other Contract', 'DSH'],
      'WAC' => ['WAC', 'Non Contract'],
      '340B' => ['340B']
    }

    mapped_types = purchase_type_mapping[params[:purchase_type].to_s.upcase] || ['GPO', 'WAC', '340B']

    query = PurchaseHistory.where(
      health_system: params[:health_system],
      generic_name_group: params[:group].upcase,
      wholesaler_purchase_type: mapped_types,
      invoice_date: start_date..end_date
    )
    query = query.where(package_description: 'SYRINGE') if params[:group].upcase == 'FILGRASTIM'

    results = query.order(:facility_name, :generic_name).select('DISTINCT ON (facility_name, generic_name, product_description) *')

    if params[:filtered_sites].present?
      return where(
        health_system: user.team_name,
        generic_name_group: params[:group],
        hospital_name: params[:filtered_sites]
      )
    elsif params[:selected_sites].present?
      return where(
        health_system: user.team_name,
        generic_name_group: params[:group],
        hospital_name: params[:selected_sites]
      )
    end

    results
  end

  def self.calculate_conversion_data(user, invoice_details, params)
    original = PurchaseHistory.find_by_id(params[:detail_id])
    conversion = BiosimilarPrice.find_by(
      extracted_strength: original.extracted_strength,
      generic_name: params[:product]
    )

    conv_cost = params[:purchase_type] == 'GPO' ? conversion.gpo_cost : conversion.cost_three_forty_b
    orig_cost = params[:purchase_type] == 'GPO' ? original.gpo_price_without_cost_dist_minus : original.price_without_cost_dist_minus

    pct = params[:percentage].to_f / 100
    total_units = total_annualized_units(original)

    conv_expense = (pct * total_units * conv_cost) + ((1 - pct) * total_units * orig_cost)
    conv_margin = (pct * total_units * ((conversion.reimbursement_per_billing_unit.to_f * conversion.billing_unit_per_package_size) - conv_cost)) +
                  ((1 - pct) * total_units * margin_per_dose_conversion(conversion, original, orig_cost))

    savings = (ann_units(original) * orig_cost) - conv_expense
    margin_gain = conv_margin - annualized_margin_per_dose(original, orig_cost)

    UsersConversionHistory.create(
      user_id: params[:user_id],
      generic_name_group: params[:group],
      conversion_product: params[:product],
      purchase_history_id: params[:detail_id],
      percentage: params[:percentage],
      conversion_annualized_expense: conv_expense,
      conversion_annualized_margin: conv_margin,
      conversion_annualized_expense_savings: savings,
      conversion_annualized_margin_improvement: margin_gain
    )

    {
      conversion_expense: conv_expense,
      conversion_margin: conv_margin,
      conversion_annualized_expense_savings: savings,
      conversion_annulized_margin_improvement: margin_gain
    }
  end

  def self.total_annualized_units(original)
    if original.total_quantity_ordered.to_f > 0 && original.package_size.to_f > 0
      (original.total_quantity_ordered.to_f / original.package_size.to_f) * 12
    else
      0
    end
  end

  def self.ann_units(original)
    if original.total_quantity_ordered.to_f > 0 && original.package_size.to_f > 0
      original.total_quantity_ordered.to_f / original.package_size.to_f * 12
    else
      0
    end
  end

  def self.margin_per_dose_conversion(conversion, original, orig_cost)
    ((conversion.reimbursement_per_billing_unit.to_f * conversion.billing_unit_per_package_size.to_f) - orig_cost.to_f).round(2)
  end

  def self.annualized_margin_per_dose(original, orig_cost)
    ((original.reimbursement_per_billing_unit.to_f * original.billing_unit_per_package_size.to_f) - orig_cost.to_f) * total_annualized_units(original)
  end

  def self.utilization_report_xlsx(version_name, data, user, totals)
    helper = ActionController::Base.helpers
    format_currency = ->(num) { helper.number_to_currency(num.to_f, unit: "$", precision: 2) }
    histories_by_report = user.utilization_conversion_histories.where(version_name: version_name).order(id: :asc).group_by(&:utilization_report_id)

    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "UTILIZATION REPORT") do |sheet|
      sheet.add_row [
        'HOSPITAL_NAME', 'ORDER_NAME', 'ORDER DATE TIME', 'ORDER_ID', 'GENERIC_NAME',
        'ORDER_DESCRIPTION', 'ADMINISTRATION_INSTANT', 'MAR_ACTION', 'QUANTITY', 'QTY_UNIT_NAME', 'STRENGTH',
        'PACK DESC', 'NDC CODE', 'PACKAGE SIZE', 'HCPCS CODE', 'CHARGE TYPE', 'CHARGE CLASS', 'FINANCIAL CLASS',
        'PRIMARY PAYOR NAME', 'BENEFIT PLAN NAME', 'ADMINISTRATION_DEPARTMENT', 'GROUP', 'BRAND NAME', 'QUARTER',
        'PRODUCT COST PER UNIT', 'TOTAL UNITS',  'CMS TOTAL UNITS', 'TOTAL PRODUCT COST', 'TOTAL INSURANCE PAYMENT', 'ACTUAL REIMBURSEMENT', 'TOTAL MARGIN', 'PERCENT MARGIN',
        'CONVERSION PRODUCT', 'CONVERSION PERCENTAGE',
        'CONVERSION PRODUCT COST PER UNIT', 'CONVERSION TOTAL PRODUCT COST', 'CONVERSION PRODUCT TOTAL INSURANCE PAYMENT',
        'CONVERSION PRODUCT TOTAL MARGIN', 'CONVERSION PRODUCT PERCENT MARGIN', 'BLENDED CONVERSION TOTAL PRODUCT COST',
        'BLENDED CONVERSION TOTAL MARGIN', 'BLENDED CONVERSION PERCENT MARGIN', 'BLENDED CONVERSION COST DIFFERENCE',
        'BLENDED CONVERSION MARGIN DIFFERENCE', 'BLENDED CONVERSION PERCENT MARGIN DIFFERENCE'
      ]

      data.each do |record|
        next unless record
        is_report = record.is_a?(UtilizationReport)
        if is_report
          uo = record.utilization_order
          pp = record.primary_payor
          ndc = record.ndc_code_record
          history = histories_by_report[record.id]&.last
          conversion = history || record.invoice_conversion

          price = (record.price_without_cost_dist_minus.to_f.round(2) * record.total_units.to_f.round(2)).round(2)
          margin = record.insurance_payment_per_dose.to_f.round(2) - price
          percent_margin = price.positive? ? ((margin / price) * 100.0).round(1) : 0.0
          actual_margin = record.actual_reimbursement.to_f.round(2) - price
          actual_percent_margin = price.positive? ? ((actual_margin / price) * 100.0).round(1) : 0.0
        else
          uo = pp = ndc = conversion = nil
          history = histories_by_report[record["id"].to_i]&.last
          conversion = history
          price = (record["priceWithoutCostDistMinus"].to_f.round(2) * record["totalUnits"].to_f.round(2)).round(2)
          margin = record["marginDoseValue"].to_f.round(2)
          percent_margin = record["percentMarginValue"].to_f.round(1)
          actual_margin = (record["insuranceValue"].to_f.round(2) - price).round(2)
          actual_percent_margin = record["percentMarginValue"].to_f.round(1)
        end

        sheet.add_row [
          is_report ? record.hospital_name : record["hospitalName"],
          uo&.order_name || record["orderName"],
          uo&.order_date_time&.strftime("%Y-%m-%d %H:%M:%S") || (record["orderDate"]&.to_datetime&.strftime("%Y-%m-%d %H:%M:%S")),
          uo&.order_id || record["orderId"],
          ndc&.generic_name || UtilizationReport.find_by(id: record["id"])&.ndc_code_record&.generic_name||record["genericName"],
          uo&.order_description || record["orderDescription"],
          (is_report ? record.administration_instant&.strftime("%Y-%m-%d %H:%M:%S") : record["administrationInstant"]&.to_datetime&.strftime("%Y-%m-%d %H:%M:%S")),
          is_report ? record.mar_action : record["marAction"],
          is_report ? record.quantity : record["quantity"],
          is_report ? record.qty_unit_name : record["qtyUnitName"],
          ndc&.strength || record["strength"],
          ndc&.package_description || record["packDesc"],
          ndc&.ndc_code || record["ndcCode"],
          ndc&.package_size || record["packageSize"],
          is_report ? record.hcpcs_code : record["hcpcsCode"],
          is_report ? record.charge_type : record["chargeType"],
          is_report ? record.charge_class : record["chargeClass"],
          is_report ? record.financial_class : record["financialClass"],
          pp&.primary_payor_name || record["payorName"],
          pp&.benefit_plan_name || record["benefitPlan"],
          is_report ? record.administration_department : record["administrationDepartment"],
          (is_report ? record.generic_name_group : record["genericNameGroup"])&.upcase,
          (ndc&.brand_name&.upcase.presence || (is_report ? record.extracted_brand_name&.upcase : record["extracted_brand_name"]&.upcase)),
          is_report ? record.accounting_period&.name : UtilizationReport.find_by(id: record["id"]).accounting_period&.name ||record["reimbursementId"] || totals[:accounting_period_name] || "All Periods",
          format_currency.call(is_report ? record.price_without_cost_dist_minus : record["priceWithoutCostDistMinus"]),
          (is_report ? record.total_units : record["totalUnits"]).to_f.round(2),
          (is_report ? record.cms_total_units : record["cms_total_units"]).to_f.round(2),
          format_currency.call(price),
          format_currency.call(is_report ? record.insurance_payment_per_dose : record["insuranceValue"]),
          format_currency.call(is_report ? record.actual_reimbursement : record["actualReimbursement"]),
          format_currency.call(margin),
          "#{percent_margin}%",
          conversion&.conversion_product || record["conversionProduct"],
          conversion.try(:conversion_percentage) || conversion.try(:percentage) || record["conversionPercentage"],
          format_currency.call(conversion&.conversion_product_cost_per_unit || record["priceValue"]),
          format_currency.call(conversion&.conversion_product_total_cost || record["costDoseTotalValue"]),
          format_currency.call(conversion&.conversion_product_total_insurance_payment || record["productPercentMarginValue"]),
          format_currency.call(conversion&.conversion_product_total_margin || record["marginDoseTotalValue"]),
          "#{conversion&.conversion_product_percent_margin&.round(1) || record["percentMarginTotalValue"]&.to_f&.round(1)}%",
          format_currency.call(conversion&.blended_conversion_cost_per_unit || record["blendedCostDoseValue"]),
          format_currency.call(conversion&.blended_conversion_total_margin || record["blendedMarginValue"]),
          "#{conversion&.blended_conversion_percent_margin&.round(1) || record["blendedPercentMarginValue"]&.to_f&.round(1)}%",
          format_currency.call(conversion&.blended_conversion_cost_difference || record["blendedCostDiffValue"]),
          format_currency.call(conversion&.blended_conversion_margin_difference || record["conversionBlendedMarginDiffValue"]),
          "#{conversion&.blended_conversion_percent_margin_difference&.round(1) || record["blendedConversionPercentMarginDifferenceValue"]&.to_f&.round(1)}%"

        ]
      end

      sheet.add_row [
        'TOTAL', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', totals[:total_units].round(0), '', format_currency.call(totals[:price_without_cost_dist_minus].round(0).to_i), '', '',
        format_currency.call(totals[:total_margin].round(0).to_i), "#{totals[:percent_margin].round(1)}%", '', '', '', '', '', '',
        '', format_currency.call(totals[:blended_conversion_cost_per_unit].round(0).to_i),
        format_currency.call(totals[:blended_conversion_total_margin].round(0).to_i),
        "#{totals[:blended_conversion_percent_margin].round(1)}%",
        format_currency.call(totals[:blended_conversion_cost_difference].round(0).to_i),
        format_currency.call(totals[:blended_conversion_margin_difference].round(0).to_i),
        "#{totals[:blended_conversion_percent_margin_difference].round(1)}%"
      ]
    end
    package.to_stream
  end

  def self.cms_reimbursement_xlsx(drugs_data, purchase_type)
    total_conversion_text = drugs_data.map { |data| data['ConversionText'].delete('$,').to_i }.sum
    total_conversion_annual_margin = drugs_data.map { |data| data['ConversionmarginText'].delete('$,').to_i }.sum
    total_annualized_savings = drugs_data.map { |data| data['ConversionsavingsText'].delete('$,').to_i }.sum
    total_annualized_improvement = drugs_data.map { |data| data['ConversionimprovementText'].delete('$,').to_i }.sum
    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Reimbursement Data") do |sheet|
      sheet.add_row [
        'PHARMACY NAME', 'BRAND NAME', 'GENERIC NAME', 'PRODUCT DESCRIPTION','PRICE W/O COST DIST MINUS', 'ANNUALIZED UNITS',
        'ANNUALIZED SPEND W/O COST MINUS', 'CMS PAYMENT PER UNIT', 'CMS PAYMENT PER DOSE', 'MARGIN PER DOSE',
        'ANNUALIZED MARGIN', 'CONVERSION PRODUCT', 'CONVERSION PERCENTAGE', 'CONVERSION ANNUALIZED EXPENSE',
        'CONVERSION ANNUALIZED MARGIN', 'CONVERSION ANNUALIZED EXPENSE SAVINGS',
        'CONVERSION ANNUALIZED MARGIN IMPROVEMENT'
      ]

      drugs_data.each do |data|
        drug = PurchaseHistory.find_by_id(data['id'])
        next unless drug.present?

        sheet.add_row [
          drug.facility_name.to_s,
          drug.brand_name.to_s,
          drug.generic_name.to_s,
          drug.product_description.to_s,
          cost(drug, purchase_type).present? ? formatted_value(cost(drug, purchase_type).to_f) : '',
          cms_reimbursement_ann_units(drug),
          formatted_value((cost(drug, purchase_type).to_f * cms_reimbursement_ann_units(drug).to_f).round(0)),
          drug.cms_payment_per_unit.to_f.round(2).to_s,
          sprintf("$%.2f", (drug.cms_payment_per_unit.to_f * billing_unit(drug))),
          (sprintf("%s$%.2f", (((drug.cms_payment_per_unit.to_f * billing_unit(drug)) - cost(drug, purchase_type).to_f) < 0 ? "-" : ""),
        ((drug.cms_payment_per_unit.to_f * billing_unit(drug)) - cost(drug, purchase_type).to_f).abs)),
          formatted_value((((drug.cms_payment_per_unit.to_f * billing_unit(drug)) - cost(drug, purchase_type).to_f) * cms_reimbursement_ann_units(drug).to_f).round(0)),
          data['selectedText'].to_s.gsub('Select products', ''),
          data['allValues'].present? ? "#{data['allValues']}%" : '',
          data['ConversionText'].to_s,
          data['ConversionmarginText'].to_s,
          data['ConversionsavingsText'].to_s,
          data['ConversionimprovementText'].to_s,
        ]
      end

      sheet.add_row [
        'TOTAL', '', '', '', '', '', '', '', '', '', '', '', '',((total_conversion_text.negative? ? '-$' : '$') +
          formatted_number(total_conversion_text.abs.round(0).to_s)).to_s, ((total_conversion_annual_margin.negative? ? '-$' : '$') +
          formatted_number(total_conversion_annual_margin.abs.round(0).to_s)).to_s,
         ((total_annualized_savings.negative? ? '-$' : '$') +
          formatted_number(total_annualized_savings.abs.round(0).to_s)).to_s, ((total_annualized_improvement.negative? ? '-$' : '$') +
          formatted_number(total_annualized_improvement.abs.round(0).to_s)).to_s
      ]
    end

    package.to_stream
  end

  def insurance_payment
    return 0 if quarter == "Quarter 1 2025" && charge_class.to_s.downcase == "inpatient"

    if quarter == "Quarter 1 2025"
      asp_data = AspCrosswalk.find_by(ndc_two: ndc_code) ||
                 AspCrosswalk.find_by(ndc_two: ndc_code.to_s.rjust(11, '0'))
      return unless asp_data

      code = asp_data.code
      bill_units = asp_data.bill_units.to_f
      cms_price = CmsAspPricing.find_by(quarter: reimbursement, hcpcs_code: code)
      return unless cms_price

      base_payment = bill_units * cms_price.payment_limit.to_f * units.to_f

      if medicare_plan? || cms_asp.blank?
        base_payment
      else
        base_payment * (cms_asp.to_f / 100.0)
      end

    elsif quarter == "Quarter 4 2024"
      biosimilar = BiosimilarPrice.find_by(
        generic_name_group: generic_name_group.to_s.upcase,
        extracted_brand_name: extracted_brand_name,
        extracted_strength: strength,
        reimbursement: reimbursement
      )
      return unless biosimilar

      base_payment = biosimilar.cms_reimbursement_per_package.to_f * units.to_f

      if medicare_plan? || cms_asp.blank?
        base_payment
      else
        base_payment * (cms_asp.to_f / 100.0)
      end
    end
  end

  def medicare_plan?
    benefit_plan_name.to_s.downcase.include?("medicare") ||
    primary_payor_name.to_s.downcase.include?("medicare")
  end

  def self.fetch_pegfil_data(user, params, scope)
    relation = scope
    relation = relation.where(hospital_name: params[:filtered_sites]) if params[:filtered_sites].present?

    if params[:start_date].present? && params[:end_date].present?
      relation = relation.joins(:utilization_order)
                         .where(utilization_orders: { order_date_time: params[:start_date]..params[:end_date] })
    end

    if params[:payor_name].present?
      relation = relation.joins(:primary_payor)
                         .where(primary_payors: { benefit_plan_name: params[:payor_name] })
    end

    if params[:charge_class].present?
      charge_class = params[:charge_class] == "Outpatient" ? %w[Outpatient Emergency] : params[:charge_class]
      relation = relation.where(charge_class: charge_class)
    end

    if params[:extracted_brand_name].present?
      selected_brands = Array(params[:extracted_brand_name]).reject(&:blank?)
      combined_relation = nil

      selected_brands.each do |brand_param|
        brand_param = brand_param.to_s.strip
        parts = brand_param.split(';').map(&:strip)
        brand_name = parts[0]
        generic_name = parts[1]
        package_size = parts[2]&.split('-')&.last

        next if brand_name.blank? && generic_name.blank?

        query = relation.joins(:ndc_code_record).where(extracted_brand_name: brand_name, ndc_code_record: { generic_name: generic_name, package_size: package_size })
        combined_relation = combined_relation.nil? ? query : combined_relation.or(query)
      end

      if combined_relation.present?
        relation = combined_relation
        rec = relation.first
        @alternatives = rec.biosimilars.pluck(:generic_name).uniq if rec.present?
      else
        @alternatives = []
        relation = combined_relation
      end
    else
      @alternatives = []
    end

    [relation, @alternatives]
  end

  def self.zero_conversion_data(original_product, conversion_product_price)
    total_units = original_product.total_units.round(2)
    product_cost_dose = total_units * conversion_product_price
    margin_per_dose = original_product.insurance_payment_per_dose - (original_product.price_without_cost_dist_minus.to_f * total_units)

    {
      conversion_product_price: conversion_product_price.round(2),
      conversion_product_cost_dose: product_cost_dose.round(2),
      conversion_product_insurance: original_product.insurance_payment_per_dose.round(2),
      conversion_margin_per_dose: margin_per_dose.round(2),
      conversion_product_percent_margin: ((margin_per_dose / product_cost_dose) * 100.0).round(1),
      conversion_blended_cost_dose: 0,
      blended_conversion_margin: 0,
      blended_conversion_percent_margin: 0,
      blended_conversion_cost_diff: 0,
      conversion_blended_margin_diff: 0,
      blended_conversion_percent_margin_difference: 0,
    }
  end

  def self.blended_conversion_data(original_product, conversion_product, conversion_price, percentage_param, version_title, current_user)
    total_units = original_product.total_units.round(2)
    original_price = original_product.price_without_cost_dist_minus.to_f.round(2)
    insurance_dose = original_product.insurance_payment_per_dose.to_f.round(2)
    insurances = original_product&.primary_payor

    conversion_cost_dose = total_units * conversion_price.round(2)

    cms_price = insurances.insurance_factor.present? ? (insurances.insurance_factor / 100.0) : 1.0

    conversion_insurance = if original_product.charge_class&.downcase == "inpatient"
                             0.0
                           elsif insurances.benefit_plan_name.to_s.downcase.include?("medicare") || insurances.primary_payor_name.to_s.downcase.include?("medicare") || !insurances.insurance_factor.present?
                             total_units * conversion_product.reimbursement_per_billing_unit.to_f * conversion_product.billing_unit_per_package_size.to_f
                           else
                             total_units * conversion_product.reimbursement_per_billing_unit.to_f * conversion_product.billing_unit_per_package_size.to_f * cms_price
                           end

    margin_per_dose = conversion_insurance.round(2) - conversion_cost_dose.round(2)
    percent_margin = (margin_per_dose / conversion_cost_dose.round(2)) * 100.0

    percentage = percentage_param.to_f / 100.0
    blended_cost_dose = (percentage * conversion_cost_dose) + ((1 - percentage) * (original_price * total_units))
    blended_margin = (percentage * margin_per_dose) + ((1 - percentage) * (insurance_dose - (original_price * total_units)))
    blended_percent_margin = (blended_margin / blended_cost_dose) * 100.0
    blended_cost_diff = blended_cost_dose - (original_price * total_units)
    blended_margin_diff = blended_margin.round(2) - (insurance_dose - (original_price * total_units))
    percent_margin_diff = blended_percent_margin.round(1) - original_product.percent_margin.round(1)

    UtilizationConversionHistory.create!(
      user_id: current_user.id,
      utilization_report_id: original_product.id,
      team_id: current_user.team_id,
      percentage: percentage_param,
      generic_name_group: original_product.generic_name_group,
      conversion_product: conversion_product.generic_name,
      conversion_product_cost_per_unit: conversion_price.round(2),
      conversion_product_total_cost: conversion_cost_dose.round(2),
      conversion_product_total_insurance_payment: conversion_insurance.round(2),
      conversion_product_total_margin: margin_per_dose.round(2),
      conversion_product_percent_margin: percent_margin.round(1),
      blended_conversion_cost_per_unit: blended_cost_dose.round(2),
      blended_conversion_total_margin: blended_margin.round(2),
      blended_conversion_percent_margin: blended_percent_margin.round(1),
      blended_conversion_cost_difference: blended_cost_diff.round(2),
      blended_conversion_margin_difference: blended_margin_diff.round(2),
      blended_conversion_percent_margin_difference: percent_margin_diff.round(1),
      accounting_period_id: original_product.accounting_period_id,
      version_name: version_title,
      status: "not_saved"
    )

    {
      conversion_product_price: conversion_price.round(2),
      conversion_product_cost_dose: conversion_cost_dose.round(2),
      conversion_product_insurance: conversion_insurance.round(2),
      conversion_margin_per_dose: margin_per_dose.round(2),
      conversion_product_percent_margin: percent_margin.round(1),
      conversion_blended_cost_dose: blended_cost_dose.round(2),
      blended_conversion_margin: blended_margin.round(2),
      blended_conversion_percent_margin: blended_percent_margin.round(1),
      blended_conversion_cost_diff: blended_cost_diff.round(2),
      conversion_blended_margin_diff: blended_margin_diff.round(2),
      blended_conversion_percent_margin_difference: percent_margin_diff.round(1),
    }
  end

  def self.formatted_number(number)
    format('%<number>.0f', number:).gsub(/(\d)(?=(\d{3})+(?!\d))/, '\\1,')
  end

  def self.formatted_value(value)
    formatted = if value.negative?
                  "-$#{value.abs.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
                else
                  "$#{value.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
                end
    formatted
  end

  def self.cost(drug, purchase_type)
    purchase_type == "GPO" ? drug.gpo_price_without_cost_dist_minus : drug.price_without_cost_dist_minus
  end

  def self.grouped_count(detail, hospital_names)
    if hospital_names.present?
      UtilizationReport.where(health_system: detail.health_system, financial_class: detail.financial_class, hcpcs_code: detail.hcpcs_code, benefit_plan_name: detail.benefit_plan_name, generic_name: detail.generic_name, hospital_name: hospital_names).count
    else
     UtilizationReport.where(health_system: detail.health_system, financial_class: detail.financial_class, hcpcs_code: detail.hcpcs_code, benefit_plan_name: detail.benefit_plan_name, generic_name: detail.generic_name).count
    end
  end

  def self.cms_reimbursement_ann_units(detail)
    start_date = Date.new(2024, 1, 1)
    end_date = Date.new(2024, 12, 31)
    PurchaseHistory.where(brand_name: detail.brand_name, generic_name_group: detail.generic_name_group, invoice_date: start_date..end_date, facility_name: detail.facility_name, product_description: detail.product_description).map(&:total_units).sum.to_i
  end

  def self.billing_unit(drug)
    BiosimilarPrice.where(generic_name_group: drug.generic_name_group, extracted_strength: drug.extracted_strength).first.billing_unit_per_package_size.to_f
  end

  def self.final_cms_payment_per_dose(detail)
    detail.cms_payment_per_unit.to_i * 12
  end

  def self.pegfil_margin_per_dose(details)
    final_cms_payment_per_dose(details) -  details.price_without_cost_dist_minus.to_f
  end

  def self.distinct_data_months_list
    distinct.pluck(:data_month).compact.uniq.sort_by do |month_str|
      Date.strptime(month_str, "%B %Y")
    rescue ArgumentError
      Date.new(9999, 1, 1) # Push invalid dates to the end
    end
  end

  private

  def calculate_margins
    return unless price_without_cost_dist_minus.present? && total_units.present? && insurance_payment_per_dose.present?

    price = price_without_cost_dist_minus.to_f.round(2)
    units = total_units.to_f.round(2)
    insurance = insurance_payment_per_dose.to_f.round(2)
    total_cost = (price * units).round(2)
    self.total_margin = (insurance - total_cost).round(2)
    self.percent_margin = ((total_margin / total_cost) * 100.0).round(2)
  end

  def cost_changed?
    saved_change_to_price_without_cost_dist_minus? ||
      saved_change_to_insurance_payment_per_dose?
  end

  def preserve_nil_for_category
    self.category = nil if category.blank?
  end
end
