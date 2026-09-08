class BiosimilarPricesController < ApplicationController
  require 'roo'

  def index
    @biosimilar_prices = BiosimilarPrice.all
  end

  def upload
    file = params[:file]

    if file.nil?
      redirect_to biosimilar_prices_path, alert: "Please select a file"
      return
    end

    spreadsheet = Roo::Spreadsheet.open(file.path)

    header = spreadsheet.row(1).map { |h| h.to_s.strip.downcase }
    last_seen = Array.new(header.size)

    (2..spreadsheet.last_row).each do |i|
      row_values = []

      header.size.times do |col|
        cell_value = spreadsheet.cell(i, col + 1)

        if cell_value.nil? || cell_value == ""
          cell_value = last_seen[col]
        else
          last_seen[col] = cell_value
        end

        row_values << cell_value
      end

      row = Hash[header.zip(row_values)]

      cleaned_generic_name =
        ActionController::Base.helpers.strip_tags(row["generic_name"].to_s)

      BiosimilarPrice.create(
        generic_name: cleaned_generic_name,
        hcpcs_code: row["hcpcs_code"],
        billing_unit: normalize_number(row["billing_unit"]),
        reimbursement_per_billing_unit: normalize_number(row["reimbursement_per_billing_unit"]),
        billing_unit_per_package_size: normalize_number(row["billing_unit_per_package_size"]),
        gpo_cost: normalize_number(row["gpo_cost"]),
        cost_three_forty_b: normalize_number(row["cost_three_forty_b"]),
        cms_reimbursement_per_package: normalize_number(row["cms_reimbursement_per_package"]),
        cms_margin_gpo_cost: normalize_number(row["cms_margin_gpo_cost"]),
        cms_margin_three_forty_b_cost: normalize_number(row["cms_margin_three_forty_b_cost"]),
        cost_per_unit_three_forty_b: normalize_number(row["cost_per_unit_three_forty_b"]),
        cms_percent_margin: normalize_number(row["cms_percent_margin"]),
        gpo_percent_margin: normalize_number(row["gpo_percent_margin"]),
        blended_cost_three_forty_b: normalize_number(row["blended cost"]),
        blended_gpo_cost: normalize_number(row["blended gpo cost"]),
        blended_cms_margin_three_forty_b_cost: normalize_number(row["blended margin"]),
        blended_cms_percent_margin: normalize_number(row["blended percent margin"]),
        blended_cms_margin_gpo_cost: normalize_number(row["blended margin gpo margin"]),
        blended_gpo_percent_margin: normalize_number(row["blended gpo percent margin"]),
        alternate_ndc_code: row["alternate_ndc_code"],
        other_ndc_codes: row["other_ndc_codes"],
        reimbursement: row["reimbursement"],
        extracted_brand_name: row["extracted_brand_name"],
        extracted_strength: row["extracted_strength"],
        generic_name_group: row["generic_name_group"],
        best_margin: row["best_margin"],
        insurances: row["insurances"],
        utilization_best_margin: row["utilization_best_margin"],
        ndc_code: row["ndc_code"],
        reimbursement_id: row["reimbursement_id"],
        accounting_period_id: row["accounting_period_id"],
        status: row["status"],
        ranked_by: row["ranked_by"],
        match: row["match"]
      )
    end

    redirect_to biosimilar_prices_path, notice: "Biosimilar Prices imported successfully!"
  end

  private

  def normalize_number(value)
    return nil if value.nil? || value == ""
    num = value.to_f

    # Format to 2 decimal places
    num.round(2)
  end
end
