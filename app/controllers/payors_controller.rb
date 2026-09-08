class PayorsController < ApplicationController
  require 'roo'

  def index
    @payors = Payor.includes(:insurances)
  end

  def upload
    file = params[:file]
    if file.nil?
      redirect_to payors_path, alert: "Please select a file."
      return
    end

    spreadsheet = Roo::Spreadsheet.open(file.path)
    header = spreadsheet.row(1).map { |h| h.to_s.strip.downcase }

    (2..spreadsheet.last_row).each do |i|
      row = Hash[[header, spreadsheet.row(i)].transpose]
      payor_name = row["payor"].to_s.strip.downcase
      generic_name = row["generic_name"].to_s.strip.downcase
      insurance_name = row["insurance"].to_s.strip.downcase

      next if payor_name.blank? || insurance_name.blank? || generic_name.blank?
      payor = Payor.find_or_create_by(name: payor_name, generic_name: generic_name)

      if payor.persisted?
        payor.insurances.find_or_create_by(name: insurance_name)
      else
        Rails.logger.warn("⚠️ Payor #{payor_name} not saved due to validation issues.")
      end
    end

    redirect_to payors_path, notice: "Payors and insurances imported successfully!"
  end
end
