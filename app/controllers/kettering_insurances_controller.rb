class KetteringInsurancesController < ApplicationController
  before_action :set_kettering_insurance, only: [ :show, :edit, :update, :destroy ]

  require "roo"

  def index
    @kettering_insurances = KetteringInsurance.order(created_at: :desc)
  end

  def show
  end

  def new
    @kettering_insurance = KetteringInsurance.new
  end

  def create
    if params[:file].present?
      import_file(params[:file])
      redirect_to kettering_insurances_path, notice: "Kettering insurance data imported successfully"
    else
      @kettering_insurance = KetteringInsurance.new(kettering_insurance_params)

      if @kettering_insurance.save
        redirect_to @kettering_insurance, notice: "Kettering insurance created successfully"
      else
        render :new, status: :unprocessable_entity
      end
    end
  rescue Roo::HeaderRowNotFoundError, ArgumentError => e
    redirect_to new_kettering_insurance_path, alert: "Unable to read the Excel file: #{e.message}"
  end

  def edit
  end

  def update
    if @kettering_insurance.update(kettering_insurance_params)
      redirect_to @kettering_insurance, notice: "Kettering insurance updated successfully"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @kettering_insurance.destroy
    redirect_to kettering_insurances_path, notice: "Kettering insurance deleted successfully"
  end

  private

  def set_kettering_insurance
    @kettering_insurance = KetteringInsurance.find(params[:id])
  end

  def kettering_insurance_params
    params.require(:kettering_insurance).permit(
      :generic_name_group, :brand_name, :primary_payor_name,
      :benefit_plan_name, :hcpcs_code, :pay_rate, :price
    )
  end

  def import_file(file)
    spreadsheet = Roo::Spreadsheet.open(file.path)
    sheet = spreadsheet.sheet(0)
    headers = sheet.row(1).map { |header| normalize_header(header) }
    required_headers = KetteringInsurance.column_names & %w[
      generic_name_group brand_name primary_payor_name benefit_plan_name
      hcpcs_code pay_rate price
    ]
    missing_headers = required_headers - headers

    raise ArgumentError, "Missing columns: #{missing_headers.map(&:humanize).join(', ')}" if missing_headers.any?

    KetteringInsurance.transaction do
      (2..sheet.last_row).each do |row_number|
        values = sheet.row(row_number)
        next if values.compact.blank?

        attributes = headers.each_with_index.each_with_object({}) do |(header, index), row|
          next unless required_headers.include?(header)

          value = ActionController::Base.helpers.strip_tags(values[index].to_s).squish
          row[header] = %w[pay_rate price].include?(header) ? normalize_number(value) : value.presence
        end

        KetteringInsurance.create!(attributes)
      end
    end
  end

  def normalize_header(header)
    header.to_s.strip.downcase.gsub(/[^a-z0-9]+/, "_").sub(/\A_/, "").sub(/_\z/, "")
  end

  def normalize_number(value)
    return nil if value.blank?

    value.to_s.delete(",").gsub(/[$%]/, "").to_d
  end
end