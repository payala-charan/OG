# frozen_string_literal: true

module UtilizationAnalyticsValidationData
  def validation_brand
    @validation_brand ||= "VAL#{SecureRandom.hex(4).upcase}"
  end

  def validation_group
    @validation_group ||= "VALGROUP#{SecureRandom.hex(3).upcase}"
  end

  def validation_ids
    @validation_ids ||= { reports: [], ndcs: [], payors: [], purchases: [], prices: [] }
  end

  def clear_validation_data
    NdcCode.where(id: validation_ids[:ndcs]).delete_all
    UtilizationAnalytics::Tables.primary_payors.where(id: validation_ids[:payors]).delete_all
    UtilizationAnalytics::Tables.utilization_reports.where(id: validation_ids[:reports]).delete_all
    UtilizationAnalytics::Tables.purchase_histories.where(id: validation_ids[:purchases]).delete_all
    NewBiosimilarPrice.where(id: validation_ids[:prices]).delete_all
  end

  def add_report!(attrs = {})
    record = UtilizationAnalytics::Tables.utilization_reports.create!(
      {
        team_id: "198",
        category: nil,
        charge_class: "Outpatient",
        generic_name_group: validation_group,
        accounting_period_id: 6,
        data_month: "April 2026",
        cms_total_units: 0,
        actual_reimbursement: 0
      }.merge(attrs)
    )
    validation_ids[:reports] << record.id
    record
  end

  def add_ndc!(report, brand: validation_brand, ndc_code: "NDC1")
    record = NdcCode.create!(utilization_report_id: report.id, ndc_code: ndc_code, brand_name: brand)
    validation_ids[:ndcs] << record.id
    record
  end

  def add_purchase!(attrs = {})
    record = UtilizationAnalytics::Tables.purchase_histories.create!(
      {
        team_id: "198",
        accounting_period_id: 6,
        data_month: "April 2026",
        brand_name: validation_brand,
        generic_name_group: validation_group,
        wholesaler_purchase_type: "340B",
        invoice_price: 10,
        total_quantity_ordered: 2,
        ndc_product_id: "AAA"
      }.merge(attrs)
    )
    validation_ids[:purchases] << record.id
    record
  end

  def add_price!(attrs = {})
    record = NewBiosimilarPrice.create!(
      {
        team_id: "198",
        accounting_period_id: 6,
        ndc_code: "AAA",
        billing_unit_per_package_size: 4
      }.merge(attrs)
    )
    validation_ids[:prices] << record.id
    record
  end

  def add_payor!(report, name: "Aetna", plan: nil)
    record = UtilizationAnalytics::Tables.primary_payors.create!(
      utilization_report_id: report.id,
      primary_payor_name: name,
      benefit_plan_name: plan
    )
    validation_ids[:payors] << record.id
    record
  end

  def seed_period!(accounting_period_id:, data_month: "April 2026")
    outpatient = add_report!(
      accounting_period_id: accounting_period_id,
      data_month: data_month,
      cms_total_units: 100,
      actual_reimbursement: 500,
      charge_class: "Outpatient",
      hospital_name: "Main"
    )
    add_ndc!(outpatient, ndc_code: "UTIL-#{accounting_period_id}-OP")
    add_payor!(outpatient, name: "Aetna")
    emergency = add_report!(
      accounting_period_id: accounting_period_id,
      data_month: data_month,
      cms_total_units: 40,
      actual_reimbursement: 80,
      charge_class: "Emergency",
      hospital_name: "Main"
    )
    add_ndc!(emergency, ndc_code: "UTIL-#{accounting_period_id}-EM")
    inpatient = add_report!(
      accounting_period_id: accounting_period_id,
      data_month: data_month,
      cms_total_units: 999,
      actual_reimbursement: 1,
      charge_class: "Inpatient",
      hospital_name: "Main"
    )
    add_ndc!(inpatient, ndc_code: "UTIL-#{accounting_period_id}-IP")
    wasted = add_report!(
      accounting_period_id: accounting_period_id,
      data_month: data_month,
      cms_total_units: 50,
      actual_reimbursement: 50,
      category: "Waste"
    )
    add_ndc!(wasted, ndc_code: "UTIL-#{accounting_period_id}-W")
    add_purchase!(
      accounting_period_id: accounting_period_id,
      data_month: data_month,
      invoice_price: 10,
      total_quantity_ordered: 2,
      ndc_product_id: "AAA"
    )
    add_purchase!(
      accounting_period_id: accounting_period_id,
      data_month: data_month,
      invoice_price: 5,
      total_quantity_ordered: 4,
      ndc_product_id: "BBB"
    )
    add_purchase!(
      accounting_period_id: accounting_period_id,
      data_month: data_month,
      invoice_price: 0,
      total_quantity_ordered: 9,
      ndc_product_id: "ZERO"
    )
    add_purchase!(
      accounting_period_id: accounting_period_id,
      data_month: data_month,
      wholesaler_purchase_type: "GPO",
      invoice_price: 100,
      total_quantity_ordered: 5,
      ndc_product_id: "GPO"
    )
  end

  def seed_standard_prices!(period_id)
    add_price!(accounting_period_id: period_id, ndc_code: "AAA", billing_unit_per_package_size: 4)
    add_price!(accounting_period_id: period_id, ndc_code: "NOPE", alternate_ndc_code: "BBB", billing_unit_per_package_size: 2)
  end

  def calculator_for(**overrides)
    UtilizationAnalytics::Calculator.new(**{
      team_id: "198",
      group: validation_group,
      charge_class: "Outpatient"
    }.merge(overrides))
  end
end
