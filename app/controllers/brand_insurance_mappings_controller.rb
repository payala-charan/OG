class BrandInsuranceMappingsController < ApplicationController
  require 'roo'
  require 'axlsx'

  def index
    @records = BrandInsuranceMapping.where(user_id: current_user.id).order(created_at: :desc)
    @last_record = @records.first
  end

  def create
    if params[:file].blank?
      flash[:alert] = "Please upload a Brand-Insurances mapping raw Excel file."
      redirect_to brand_insurance_mappings_path and return
    end

    uploaded_file = params[:file]
    begin
      spreadsheet = Roo::Spreadsheet.open(uploaded_file.path)
      sheet = spreadsheet.sheet(0)

      header_row = sheet.row(1).map(&:to_s).map(&:strip)
      
      if header_row.size < 2
        flash[:alert] = "The Excel file must have at least two columns: Insurance column and at least one Brand column."
        redirect_to brand_insurance_mappings_path and return
      end

      brand_names = header_row[1..-1]
      brand_mappings = {}
      brand_names.each do |brand|
        brand_mappings[brand] = [] unless brand.blank?
      end

      (2..sheet.last_row).each do |r_idx|
        row = sheet.row(r_idx)
        next if row.all?(&:nil?)

        insurance_cell = row[0]
        next if insurance_cell.to_s.strip.blank?

        insurances = insurance_cell.to_s.split(',').map(&:strip).reject(&:empty?)

        (1...header_row.size).each do |c_idx|
          brand_name = header_row[c_idx]
          next if brand_name.blank?

          cell_val = row[c_idx].to_s.strip.upcase
          if cell_val == 'Y' || cell_val == 'X'
            brand_mappings[brand_name] ||= []
            brand_mappings[brand_name].concat(insurances)
          end
        end
      end

      brand_mappings.each do |brand_name, insurances_list|
        brand_mappings[brand_name] = insurances_list.uniq.compact
      end

      record = BrandInsuranceMapping.create!(
        user_id: current_user.id,
        user_email: current_user.email,
        file_name: uploaded_file.original_filename,
        mappings: brand_mappings
      )

      flash[:notice] = "Brand mapping file processed successfully!"
      redirect_to brand_insurance_mapping_path(record)
    rescue => e
      flash[:alert] = "Failed to process the uploaded file: #{e.message}"
      Rails.logger.error("Brand mappings parse error: #{e.message}\n#{e.backtrace.join("\n")}")
      redirect_to brand_insurance_mappings_path
    end
  end

  def show
    @record = BrandInsuranceMapping.find(params[:id])
    @mappings = @record.parsed_mappings
  end

  def download
    @record = BrandInsuranceMapping.find(params[:id])
    @mappings = @record.parsed_mappings

    package = Axlsx::Package.new
    workbook = package.workbook

    title_style = workbook.styles.add_style(b: true, sz: 14, fg_color: "FFFFFF", bg_color: "4361EE", alignment: { horizontal: :center })
    header_style = workbook.styles.add_style(b: true, sz: 11, fg_color: "FFFFFF", bg_color: "2B2D42", alignment: { horizontal: :center, vertical: :center })
    border = workbook.styles.add_style(border: { style: :thin, color: "DDDDDD" })
    zebra_style = workbook.styles.add_style(bg_color: "F8F9FC", border: { style: :thin, color: "DDDDDD" })

    workbook.add_worksheet(name: "Summary Mapping") do |sheet|
      sheet.add_row ["Brand-Insurances Summary Mapping Report"], style: title_style
      sheet.merge_cells("A1:C1")
      sheet.add_row []

      sheet.add_row ["Brand Name", "Mapped Insurances Count", "Mapped Insurances List"], style: header_style
      
      row_idx = 0
      @mappings.each do |brand, insurances|
        current_style = row_idx.even? ? border : zebra_style
        sheet.add_row [brand, insurances.size, insurances.join(', ')], style: current_style
        row_idx += 1
      end

      sheet.column_widths 30, 25, 80
    end

    workbook.add_worksheet(name: "Detailed Line-by-Line") do |sheet|
      sheet.add_row ["Brand-Insurances Detailed Line-by-Line Report"], style: title_style
      sheet.merge_cells("A1:B1")
      sheet.add_row []

      sheet.add_row ["Brand Name", "Insurance Name"], style: header_style

      row_idx = 0
      @mappings.each do |brand, insurances|
        insurances.each do |ins|
          current_style = row_idx.even? ? border : zebra_style
          sheet.add_row [brand, ins], style: current_style
          row_idx += 1
        end
      end

      sheet.column_widths 30, 60
    end

    filename = "brand_insurance_mappings_#{@record.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}.xlsx"
    
    # Store temporary file in Rails root tmp directory
    temp_file_path = Rails.root.join('tmp', filename).to_s
    package.serialize(temp_file_path)

    send_file temp_file_path, filename: filename, type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", disposition: "attachment"
  end

  def clear_history
    BrandInsuranceMapping.where(user_id: current_user.id).destroy_all
    flash[:notice] = "Mapping history cleared successfully."
    redirect_to brand_insurance_mappings_path
  end
end
