class PaymentFactorsController < ApplicationController
  require 'roo'

  def index
    @payment_factors = PaymentFactor.all
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
      # Convert all string values in the row to lowercase
      row.transform_values! { |v| v.is_a?(String) ? v.strip.downcase : v }
      PaymentFactor.create(
        payor: row["payor"],
        factor: row["factor"]
      )
    end

    redirect_to root_path, notice: "Payment Factors imported successfully!"
  end
end
