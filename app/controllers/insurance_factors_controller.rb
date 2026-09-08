# class InsuranceFactorsController < ApplicationController
#   before_action :set_insurance_factor, only: [:show, :edit, :update, :destroy]

#   require 'roo'

#   # ✅ INDEX
#   def index
#     @insurance_factors = InsuranceFactor.order(created_at: :desc)
#   end

#   # ✅ SHOW
#   def show
#   end

#   # ✅ NEW
#   def new
#     @insurance_factor = InsuranceFactor.new
#   end

#   # ✅ CREATE (Manual + Excel Upload)
#   def create
#     if params[:file].present?
#       import_file(params[:file])
#       redirect_to insurance_factors_path, notice: "File uploaded successfully"
#     else
#       @insurance_factor = InsuranceFactor.new(insurance_factor_params)

#       if @insurance_factor.save
#         redirect_to @insurance_factor, notice: "Created successfully"
#       else
#         render :new
#       end
#     end
#   end

#   # ✅ EDIT
#   def edit
#   end

#   # ✅ UPDATE
#   def update
#     if @insurance_factor.update(insurance_factor_params)
#       redirect_to @insurance_factor, notice: "Updated successfully"
#     else
#       render :edit
#     end
#   end

#   # ✅ DELETE
#   def destroy
#     @insurance_factor.destroy
#     redirect_to insurance_factors_path, notice: "Deleted successfully"
#   end

#   private

#   def set_insurance_factor
#     @insurance_factor = InsuranceFactor.find(params[:id])
#   end

#   def insurance_factor_params
#     params.require(:insurance_factor).permit(
#       :primary_payor_name,
#       :benefit_plan_name,
#       :category,
#       :rate_percent,
#       :insurance_factor,
#       :team_id
#     )
#   end

#   # ✅ Excel Import
#   def import_file(file)
#     valid_columns = InsuranceFactor.column_names

#     xlsx = Roo::Spreadsheet.open(file.path)
#     sheet = xlsx.sheet(0)

#     headers = sheet.row(1).map do |h|
#       h.to_s.strip.downcase.gsub(/\s+/, "_")
#     end

#     (2..sheet.last_row).each do |i|
#       row = sheet.row(i)
#       next if row.compact.blank?

#       normalized_row = {}

#       headers.each_with_index do |header, index|
#         next if header.blank?

#         value = row[index]

#         clean_value = ActionController::Base.helpers.strip_tags(value.to_s).squish

#         if ["rate_percent", "insurance_factor"].include?(header)
#             if clean_value.blank?
#                 normalized_row[header] = header == "rate_percent" ? 100.0 : 1.0
#             else
#                 value = clean_value.gsub('%', '')
#                 normalized_row[header] = value.to_f
#             end
#         else
#             normalized_row[header] = clean_value.presence
#         end
#       end

#       InsuranceFactor.create!(normalized_row)
#     end
#   end
# end


class InsuranceFactorsController < ApplicationController
  before_action :set_insurance_factor, only: [:show, :edit, :update, :destroy]

  require 'roo'

  # ✅ INDEX
  def index
    @insurance_factors = InsuranceFactor.order(created_at: :desc)
  end

  # ✅ SHOW
  def show
  end

  # ✅ NEW
  def new
    @insurance_factor = InsuranceFactor.new
  end

  # ✅ CREATE (Manual + Excel Upload)
  def create
    if params[:file].present?
      import_file(params[:file])
      redirect_to insurance_factors_path, notice: "File uploaded successfully"
    else
      @insurance_factor = InsuranceFactor.new(insurance_factor_params)

      if @insurance_factor.save
        redirect_to @insurance_factor, notice: "Created successfully"
      else
        render :new
      end
    end
  end

  # ✅ EDIT
  def edit
  end

  # ✅ UPDATE
  def update
    if @insurance_factor.update(insurance_factor_params)
      redirect_to @insurance_factor, notice: "Updated successfully"
    else
      render :edit
    end
  end

  # ✅ DELETE
  def destroy
    @insurance_factor.destroy
    redirect_to insurance_factors_path, notice: "Deleted successfully"
  end

  private

  # ✅ CALLBACK
  def set_insurance_factor
    @insurance_factor = InsuranceFactor.find(params[:id])
  end

  # ✅ STRONG PARAMS
  def insurance_factor_params
    params.require(:insurance_factor).permit(
      :primary_payor_name,
      :benefit_plan_name,
      :category,
      :rate_percent,
      :insurance_factor,
      :team_id
    )
  end

  # ✅ EXCEL IMPORT (FIXED & SAFE)
  def import_file(file)
    valid_columns = InsuranceFactor.column_names

    # ✅ Header Mapping (IMPORTANT FIX)
    header_mapping = {
      "rate_%" => "rate_percent"
    }

    xlsx = Roo::Spreadsheet.open(file.path)
    sheet = xlsx.sheet(0)

    # ✅ Normalize + Map Headers
    headers = sheet.row(1).map do |h|
      normalized = h.to_s.strip.downcase.gsub(/\s+/, "_")
      header_mapping[normalized] || normalized
    end

    (2..sheet.last_row).each do |i|
      row = sheet.row(i)
      next if row.compact.blank?

      normalized_row = {}

      headers.each_with_index do |header, index|
        next if header.blank?
        next unless valid_columns.include?(header)  # ✅ prevent unknown attribute error

        value = row[index]
        clean_value = ActionController::Base.helpers.strip_tags(value.to_s).squish

        if ["rate_percent", "insurance_factor"].include?(header)
          if clean_value.blank?
            normalized_row[header] = header == "rate_percent" ? 100.0 : 1.0
          else
            normalized_row[header] = clean_value.gsub('%', '').to_f
          end
        else
          normalized_row[header] = clean_value.presence
        end
      end

      # ✅ Create Record Safely
      InsuranceFactor.create!(normalized_row)
    end
  end
end

