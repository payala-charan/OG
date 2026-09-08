class ProductPreferenceRecordsController < ApplicationController

  # Upload page
  def new
  end

  def create
    if params[:file].blank?
        redirect_to new_product_preference_record_path, alert: "Please upload a file"
        return
    end

    file = params[:file]

    begin
        excel = Roo::Spreadsheet.open(file.path)
        sheet = excel.sheet(0)

        headers = sheet.row(1).map { |h| h.to_s.strip }

        rows = []

        (2..sheet.last_row).each do |i|
        row_data = sheet.row(i)
        row_hash = {}

        headers.each_with_index do |header, index|
            row_hash[header] = row_data[index]
        end

        # 🔥 Apply validation
        validator = ProductPreferenceValidatorService.new(row_hash)

        rows << {
            original_data: row_hash,
            validations: validator.call
        }
        end

        # 🔥 OPTION B: Keep only latest upload per user
        ProductPreferenceRecord.where(user_id: current_user&.id).destroy_all

        record = ProductPreferenceRecord.create!(
        data: {
            headers: headers,
            rows: rows
        },
        user_id: current_user&.id,
        user_email: current_user&.email
        )

        redirect_to product_preference_record_path(record), notice: "File uploaded and validated successfully"

    rescue => e
        redirect_to new_product_preference_record_path, alert: "Error: #{e.message}"
    end
  end

  # Show uploaded data
  def show
    @record = ProductPreferenceRecord.find(params[:id])
    @headers = @record.data["headers"]
    @rows = @record.data["rows"]
  end

  # List all uploads
  def index
    @records = ProductPreferenceRecord.order(created_at: :desc)
  end
end