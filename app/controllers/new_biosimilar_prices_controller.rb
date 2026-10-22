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
      result = import_file(params[:file])
      redirect_to new_biosimilar_prices_path,
        notice: "Imported #{result[:rows]} rows from #{result[:sheets]} sheets"
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
      :cms_reimbursement_per_billing_unit, :billing_unit_per_package_size,
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
      :blended_gpo_percent_margin, :ranked_by, :match, :team_id,
      :payrate_reimbursement_per_billing_unit,
      :payrate_reimbursement_per_package, :category,
      :cms_margin_per_unit_three_forty_b_cost, :cost_per_unit_gpo,
      :cms_margin_per_unit_gpo,
      insurances_payments: {}
    )
  end
  # Spreadsheet headers that do not match a database column name.
  BIOSIMILAR_HEADER_MAPPING = {
    "blended_340b_cost" => "blended_cost_three_forty_b",
    "blended_340b_margin" => "blended_cms_margin_three_forty_b_cost",
    "blended_percent_margin" => "blended_cms_percent_margin",
    "blended_gpo_margin" => "blended_cms_margin_gpo_cost",
    "blended_gpo_percent_margin" => "blended_gpo_percent_margin",
    "cms_margin_340b_cost" => "cms_margin_three_forty_b_cost",
    "aetna_insurances" => "aetna_inusurances"
  }.freeze

  # Column order of the commercial pricing master. Used only when a header
  # cell is blank or corrupted but the rest of the tab still matches this layout.
  BIOSIMILAR_TEMPLATE_COLUMNS = %w[
    generic_name
    match
    ndc_code
    alternate_ndc_code
    other_ndc_codes
    hcpcs_code
    billing_unit
    cms_reimbursement_per_billing_unit
    billing_unit_per_package_size
    cms_reimbursement_per_package
    insurances
    payrate_reimbursement_per_billing_unit
    payrate_reimbursement_per_package
    cost_three_forty_b
    cost_per_unit_three_forty_b
    blended_cost_three_forty_b
    cms_margin_three_forty_b_cost
    cms_margin_per_unit_three_forty_b_cost
    blended_cms_margin_three_forty_b_cost
    cms_percent_margin
    blended_cms_percent_margin
    gpo_cost
    cost_per_unit_gpo
    blended_gpo_cost
    cms_margin_gpo_cost
    cms_margin_per_unit_gpo
    blended_cms_margin_gpo_cost
    gpo_percent_margin
    blended_gpo_percent_margin
    accounting_period_id
    reimbursement_id
    generic_name_group
    status
    team_id
  ].freeze

  IGNORED_IMPORT_COLUMNS = %w[id created_at updated_at].freeze

  def import_file(file)
    xlsx = Roo::Spreadsheet.open(file.path)
    imported_rows = 0

    NewBiosimilarPrice.transaction do
      xlsx.sheets.each do |sheet_name|
        imported_rows += import_biosimilar_sheet(xlsx.sheet(sheet_name), sheet_name)
      end
    end

    { rows: imported_rows, sheets: xlsx.sheets.size }
  end

  def import_biosimilar_sheet(sheet, sheet_name)
    return 0 if sheet.last_row.nil? || sheet.last_row < 2

    headers = biosimilar_headers(sheet.row(1))
    imported = 0

    (2..sheet.last_row).each do |i|
      row = sheet.row(i)
      next if row.compact.blank?

      normalized_row = {}
      row_by_header = {}

      headers.each_with_index do |header, index|
        next if header.blank?

        value = row[index]
        row_by_header[header] = value
        next if blank_import_value?(value)
        next if IGNORED_IMPORT_COLUMNS.include?(header)

        assign_biosimilar_cell(normalized_row, header, value)
      end

      next if normalized_row.except("category").blank?

      normalized_row["category"] = sheet_name.to_s.strip
      normalized_row["insurances_payments"] = NewBiosimilarPrice.build_insurances_payments(row_by_header)
      NewBiosimilarPrice.create!(normalized_row)
      imported += 1
    end

    imported
  end

  def biosimilar_headers(raw_headers)
    mapped = raw_headers.map { |header| map_biosimilar_header(header) }
    return mapped unless biosimilar_template_layout?(mapped)

    mapped.each_with_index.map do |header, index|
      next header if importable_biosimilar_column?(header)

      template_column = BIOSIMILAR_TEMPLATE_COLUMNS[index]
      importable_biosimilar_column?(template_column) ? template_column : header
    end
  end

  def map_biosimilar_header(header)
    normalized = header.to_s.strip.downcase.gsub(/\s+/, "_")
    BIOSIMILAR_HEADER_MAPPING[normalized] || normalized
  end

  def biosimilar_template_layout?(headers)
    matches = BIOSIMILAR_TEMPLATE_COLUMNS.each_with_index.count do |column, index|
      headers[index] == column
    end
    matches >= (BIOSIMILAR_TEMPLATE_COLUMNS.length * 0.8)
  end

  def importable_biosimilar_column?(header)
    header.present? && NewBiosimilarPrice.column_names.include?(header)
  end

  def assign_biosimilar_cell(row, header, value)
    case header
    when "new_insurances"
      row["insurances"] = import_string(value)
    when "insurances"
      row["insurances"] = import_string(value) if row["insurances"].blank?
    else
      return unless importable_biosimilar_column?(header)

      row[header] = cast_biosimilar_value(header, value)
    end
  end

  def cast_biosimilar_value(header, value)
    column = NewBiosimilarPrice.columns_hash[header]
    return import_string(value) if column.nil?

    if column.type == :boolean
      ActiveModel::Type::Boolean.new.cast(value)
    elsif column.array
      import_string_array(value)
    elsif %i[float integer decimal].include?(column.type)
      import_number(value)
    else
      import_string(value)
    end
  end

  def import_string(value)
    text = value.is_a?(Numeric) ? import_numeric_identifier(value) : ActionController::Base.helpers.strip_tags(value.to_s)
    text.to_s.strip.presence
  end

  def import_string_array(value)
    return value if value.is_a?(Array)

    import_string(value).to_s.split(",").map(&:strip).reject(&:blank?)
  end

  def import_number(value)
    return value if value.is_a?(Numeric)

    raw = ActionController::Base.helpers.strip_tags(value.to_s).gsub(/[$,]/, "").strip
    return nil if raw.blank?

    Float(raw.delete("%"))
  rescue ArgumentError, TypeError
    nil
  end

  def import_numeric_identifier(value)
    if value.is_a?(Float) && value.finite? && (value % 1).zero? && value.abs < 1_000_000_000_000_000
      value.to_i.to_s
    else
      value.to_s
    end
  end

  def blank_import_value?(value)
    value.nil? || (value.is_a?(String) && value.strip.blank?)
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
      "quarter 1 2026" => 6,
      "quarter 2 2026" => 7,
      "quarter 3 2026" => 8
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
