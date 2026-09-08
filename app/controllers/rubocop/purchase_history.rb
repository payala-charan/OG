# frozen_string_literal: true
class PurchaseHistory < ApplicationRecord
  has_many :users_conversion_histories
  belongs_to :accounting_period
  has_one :facility, dependent: :destroy
  has_one :product_detail, dependent: :destroy
  has_one :purchase_metric, dependent: :destroy

  GPO = ['Premier 503B', 'Premier Contract', 'Other Contract', 'DSH', 'GPO'].freeze
  WAC = ['WAC', 'Non Contract'].freeze
  B340 = ['340B'].freeze

  scope :by_health_system, ->(hs) { where(health_system: hs) }
  scope :by_generic_group, ->(group) { where(generic_name_group: group.upcase) }
  scope :by_wholesaler_types, ->(types) { where(wholesaler_purchase_type: types) }
  scope :by_date_range, ->(start_date, end_date) { where(invoice_date: start_date..end_date) }
  scope :with_brands, ->(brands) { where(brand_name: brands) if brands.present? }

  scope :by_gpo, -> { where(wholesaler_purchase_type: GPO).includes(:purchase_metric) }
  scope :by_wac, -> { where(wholesaler_purchase_type: WAC).includes(:purchase_metric) }
  scope :by_three_forty_b, -> { where(wholesaler_purchase_type: B340).includes(:purchase_metric) }


  scope :not_generic_name_group, -> { where.not(generic_name_group: nil) }

  scope :with_metrics_sum, -> {
    includes(:purchase_metric)
      .sum('COALESCE(purchase_metrics.total_spend, 0)::float')
  }

  scope :total_spend_sum, -> {
    all.map(&:total_spend).sum.to_i
  }

  scope :by_group, ->(group) { where(generic_name_group: group)if group.present? }
  scope :by_brand, ->(brand) { where(brand_name: brand) }

  # scope :with_pricing_type, ->(type) { where(wholesaler_purchase_type: type) if type.present? }

  scope :monthly_spend, -> {
  joins(:purchase_metric)
    .group_by_month(:invoice_date, format: "%b %Y")
    .sum("CAST(purchase_metrics.total_spend AS FLOAT)")
  }

  scope :monthly_units, -> {
    joins(:purchase_metric)
      .group_by_month(:invoice_date, format: "%b %Y")
      .sum("CAST(purchase_metrics.total_units AS FLOAT)")
  }

  scope :quarterly_spend, -> {
    joins(:purchase_metric)
      .group_by_quarter(:invoice_date, series: false) # let groupdate build quarters
      .sum("CAST(purchase_metrics.total_spend AS FLOAT)")
      .transform_keys { |date| "#{date.year} Q#{((date.month - 1) / 3) + 1}" }
  }

  scope :quarterly_units, -> {
    joins(:purchase_metric)
      .group_by_quarter(:invoice_date, series: false)
      .sum("CAST(purchase_metrics.total_units AS FLOAT)")
      .transform_keys { |date| "#{date.year} Q#{((date.month - 1) / 3) + 1}" }
  }

  def self.open_spreadsheet(file)
    filename = file.respond_to?(:original_filename) ? file.original_filename : file.path
    extension = File.extname(filename)

    case extension
    when '.csv'  then Roo::CSV.new(file.path)
    when '.xls'  then Roo::Excel.new(file.path)
    when '.xlsx' then Roo::Excelx.new(file.path)
    else
      raise "Unknown file type: #{filename}"
    end
  end


  def self.build_headers(row, team_id)
    rule_engine = rule_engine_for_team(team_id)
    raise "RuleEngine not found for team #{team_id}" unless rule_engine

    header_mappings =
      rule_engine.header_aliases&.dig("purchase_file") || {}

    headers = {}

    row.each_with_index do |x, i|
      next if x.nil? || x.to_s.strip == ""

      raw_header = x.to_s.strip
      normalized =
        raw_header.downcase.scan(/[a-z0-9]+/).join("_")

      mapped_key =
        header_mappings.find do |key, _|
          key.downcase.scan(/[a-z0-9]+/).join("_") == normalized
        end&.last

      headers[mapped_key || normalized] = i
    end

    expected = expected_headers(team_id)
    missing_headers = expected - headers.keys.map(&:to_s)

    unless missing_headers.empty?
      raise "Missing required header entry '#{missing_headers.first}'"
    end

    headers
  end

  def self.expected_headers(team_id)
    rule_engine = rule_engine_for_team(team_id)
    raise "RuleEngine not found for team #{team_id}" unless rule_engine

    rule_engine.header_rules["purchase_file"].map(&:to_s)
  end


  def self.rule_engine_for_team(team_id)
    RuleEngine.find_by(team_id: team_id)
  end



  def self.process_file(parsed_file, team_id: nil, source_key: nil)
    batch      = []
    batch_size = 500
    total_rows = 0

    @headers      = {}
    @current_team_id = team_id

    all_sheets = parsed_file.sheets

    all_sheets.each do |sheet|
      parsed_file.default_sheet = sheet

      parsed_file.each_with_index do |row, i|
        if i.zero?
          @headers = build_headers(row, team_id)
        else
          # Skip rows where only one column has data — footer/note rows from the client
          filled = row.count { |cell| cell.to_s.strip.present? }
          next if filled <= 1
          batch << row
        end

        if batch.size >= batch_size
          process_row(batch, team_id)
          batch = []
        end

        total_rows = i
      end
    end

    process_row(batch, team_id) if batch.any?
    total_rows
  end

  def self.process_row(batch, team_id = nil)
    return if batch.blank?
    PurchaseHistoryImportJob.perform_now(batch, @headers, team_id || @current_team_id)
  end
end
