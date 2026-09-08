class NewBiosimilarPricesController < ApplicationController
  before_action :set_new_biosimilar_price, only: [ :show, :edit, :update, :destroy ]
  require "csv"
  # ✅ INDEX
  def index
    @new_biosimilar_prices = NewBiosimilarPrice.all
    if params[:generic_name].present?
        @new_biosimilar_prices = @new_biosimilar_prices
        .where("LOWER(generic_name) LIKE ?", "%#{params[:generic_name].downcase}%")
    end
    if params[:ndc_code].present?
        @new_biosimilar_prices = @new_biosimilar_prices
        .where("ndc_code LIKE ?", "%#{params[:ndc_code]}%")
    end
    @new_biosimilar_prices = @new_biosimilar_prices.order(created_at: :asc)
  end
  # ✅ SHOW
  def show
  end
  # ✅ NEW
  def new
    @new_biosimilar_price = NewBiosimilarPrice.new
  end
  # ✅ CREATE (Manual form + CSV Upload)
  def create
    if params[:file].present?
      import_file(params[:file])
      redirect_to new_biosimilar_prices_path, notice: "File uploaded successfully"
    else
      @new_biosimilar_price = NewBiosimilarPrice.new(new_biosimilar_price_params)

      if @new_biosimilar_price.save
        redirect_to @new_biosimilar_price, notice: "Created successfully"
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
    if @new_biosimilar_price.update(new_biosimilar_price_params)
      redirect_to @new_biosimilar_price, notice: "Updated successfully"
    else
      render :edit
    end
  end
  # ✅ DELETE
  def destroy
    @new_biosimilar_price.destroy
    redirect_to new_biosimilar_prices_path, notice: "Deleted successfully"
  end
  def upload_blended_costs
  end
  # ✅ Process blended file
  def import_blended_costs
    # debugger
    if params[:file].blank?
      redirect_to upload_blended_costs_new_biosimilar_prices_path, alert: "Please upload a file"
      return
    end

    process_blended_file(params[:file])

    redirect_to new_biosimilar_prices_path, notice: "Blended costs updated successfully"
  end
  private
  # ✅ CALLBACK
  def set_new_biosimilar_price
    @new_biosimilar_price = NewBiosimilarPrice.find(params[:id])
  end
  # ✅ STRONG PARAMS
  def new_biosimilar_price_params
    params.require(:new_biosimilar_price).permit(
      :generic_name, :hcpcs_code, :billing_unit,
      :reimbursement_per_billing_unit, :billing_unit_per_package_size,
      :gpo_cost, :cost_three_forty_b, :extracted_brand_name,
      :cms_reimbursement_per_package, :cms_margin_gpo_cost,
      :cms_margin_three_forty_b_cost, :generic_name_group,
      :extracted_strength, :best_margin, :insurances,
      :utilization_best_margin, :reimbursement, :ndc_code,
      :status, :alternate_ndc_code, :other_ndc_codes,
      :reimbursement_id, :accounting_period_id,
      :cost_per_unit_three_forty_b, :cms_percent_margin,
      :gpo_percent_margin, :blended_cost_three_forty_b,
      :blended_gpo_cost, :blended_cms_margin_three_forty_b_cost,
      :blended_cms_percent_margin, :blended_cms_margin_gpo_cost,
      :blended_gpo_percent_margin, :ranked_by, :match, :team_id
    )
  end
  def import_file(file)
      valid_columns = NewBiosimilarPrice.column_names

      header_mapping = {
        "blended_340b_cost" => "blended_cost_three_forty_b",
        "blended_340b_margin" => "blended_cms_margin_three_forty_b_cost",
        "blended_percent_margin" => "blended_cms_percent_margin",
        "blended_gpo_margin" => "blended_cms_margin_gpo_cost",
        "blended_gpo_percent_margin" => "blended_gpo_percent_margin",
        "cms_margin_340b_cost" => "cms_margin_three_forty_b_cost"
      }

      xlsx = Roo::Spreadsheet.open(file.path)
      sheet = xlsx.sheet(0)

      headers = sheet.row(1).map do |header|
          normalized = header.to_s.strip.downcase.gsub(/\s+/, "_")
          header_mapping[normalized] || normalized
      end

      (2..sheet.last_row).each do |i|
          row = sheet.row(i)

          # ✅ Skip empty rows
          next if row.compact.blank?

          normalized_row = {}

          # headers.each_with_index do |header, index|
          #   next if header.blank?

          #   value = row[index]

          #   # ✅ Remove HTML tags
          #   clean_value = ActionController::Base.helpers.strip_tags(value.to_s)

          #   if valid_columns.include?(header)
          #       if ["best_margin", "utilization_best_margin"].include?(header)
          #       normalized_row[header] = ActiveModel::Type::Boolean.new.cast(clean_value)
          #       else
          #       normalized_row[header] = clean_value.presence
          #       end
          #   end
          # end

          headers.each_with_index do |header, index|
            next if header.blank?

            value = row[index]
            clean_value = ActionController::Base.helpers.strip_tags(value.to_s).presence

            case header
            when "new_insurances"
              # ✅ Only override if present
              if clean_value.present?
                normalized_row["insurances"] = clean_value
              end

            when "insurances"
              # ✅ Only set if not already set by new_insurances
              if normalized_row["insurances"].blank?
                normalized_row["insurances"] = clean_value
              end

            else
              if valid_columns.include?(header)
                if [ "best_margin", "utilization_best_margin" ].include?(header)
                  normalized_row[header] = ActiveModel::Type::Boolean.new.cast(clean_value)
                else
                  normalized_row[header] = clean_value
                end
              end
            end
          end

          NewBiosimilarPrice.create!(normalized_row)
      end
  end
  # ✅ Process blended Excel
  def process_blended_file(file)
    xlsx  = Roo::Spreadsheet.open(file.path)
    sheet = xlsx.sheet(0)

    headers = sheet.row(1).map { |h| h.to_s.strip.downcase.gsub(/\s+/, "_") }

    (2..sheet.last_row).each do |i|
      row = sheet.row(i)
      next if row.compact.blank?

      data = {}

      headers.each_with_index do |header, index|
        data[header] = row[index]
      end

      update_blended_record(data)
    end
  end


  # ✅ Matching + Updating
  def update_blended_record(data)
    # mapped_period_id = case data["quarter"]&.to_s&.strip&.downcase
    #                    when "quarter 4 2024" then 1
    #                    when "quarter 1 2025" then 2
    #                    when "quarter 2 2025" then 3
    #                    when "quarter 3 2025" then 4
    #                    when "quarter 4 2025" then 5
    #                    when "Quar ter 1 2026" then 6
    #                    else nil
    #                    end
    quarter_mapping = {
      "quarter 4 2024" => 1,
      "quarter 1 2025" => 2,
      "quarter 2 2025" => 3,
      "quarter 3 2025" => 4,
      "quarter 4 2025" => 5,
      "quarter 1 2026" => 6
    }
    # debugger
    mapped_period_id = quarter_mapping[data["quarter"]&.to_s&.strip&.downcase]

    record = NewBiosimilarPrice.find_by(
      generic_name_group:   data["generic_name_group"]&.strip,
      generic_name:         data["generic_name"]&.strip,
      ndc_code:             data["ndc_code"]&.to_s&.strip&.sub(/\.0$/, ''), #data["ndc_code"]&.to_s.strip
      team_id:              data["team_id"] || "209", # fallback if not in file
      accounting_period_id: mapped_period_id
    )

    return unless record

    record.update(
      blended_cost_three_forty_b:            parse_currency(data["blended_cost_340b"]),
      blended_gpo_cost:                      parse_currency(data["blended_gpo_cost"]),
      blended_cms_margin_three_forty_b_cost: parse_currency(data["blended_cms_margin_340b_cost"]),
      blended_cms_percent_margin:            parse_percentage(data["blended_cms_percent_margin"]),
      blended_cms_margin_gpo_cost:           parse_currency(data["blended_cms_margin_gpo_cost"]),
      blended_gpo_percent_margin:            parse_percentage(data["blended_gpo_percent_margin"])
    )
  end


  # ✅ Helpers
  def parse_currency(value)
    return nil if value.blank?
    value.to_s.gsub(/[$,]/, "").to_f
  end

  def parse_percentage(value)
    return nil if value.blank?
    value.to_s.gsub("%", "").to_f
  end
end
