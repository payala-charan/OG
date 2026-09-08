class OgController < ApplicationController
  require 'roo'

  def index
    @og = Og.all
  end

  def upload
    file = params[:file]

    if file.nil?
      redirect_to root_path, alert: "Please select a file"
      return
    end

    # Open the Excel file
    spreadsheet = Roo::Spreadsheet.open(file.path)

    header = spreadsheet.row(1).map { |h| h.to_s.strip.downcase } 
    (2..spreadsheet.last_row).each do |i|
      row = Hash[[header, spreadsheet.row(i)].transpose]
      cleaned_generic_name = ActionController::Base.helpers.strip_tags(row["generic_name"].to_s)
      Og.create(
        generic_name: cleaned_generic_name,
        brand: row["brand"],
        strength: row["strength"],
        ndc_code: row["ndc_code"],
        reimbursement_per_billing_unit: row["reimbursement_per_billing_unit"],
        billing_unit_per_package_size: row["billing_unit_per_package_size"],
        cms_reimbursement_per_package: row["cms_reimbursement_per_package"],
        cost_three_forty_b: row["cost_three_forty_b"],
        cms_margin_three_forty_b_cost: row["cms_margin_three_forty_b_cost"],
        gpo_cost: row["gpo_cost"],
        accounting_period_id: row["accounting_period_id"],
        reimbursement_id: row["reimbursement_id"],
        generic_name_group: row["generic_name_group"],
        cms_percent_margin: row["cms_percent_margin"],
        match: row["match"],
        blended_cost_340B: row["blended_cost"],
        blended_cms_margin_340B: row["blended_margin"], 
        blended_cms_340B_percent_margin: row["blended_percent_margin"],
        blended_cost_gpo: row["blended_gpo_cost"],
        blended_cms_margin_gpo: row["blended_margin_gpo_margin"],
        blended_gpo_percent_margin: row["blended_gpo_percent_margin"]

      )
    end

    redirect_to root_path, notice: "OG imported successfully!"
  end
end
