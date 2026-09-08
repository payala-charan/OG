class PricingCatalog < ApplicationRecord
  has_paper_trail on: [:update]

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

  def self.process_file(parsed_file, team_id: nil, source_key: nil, category: nil)
    raise ArgumentError, "team_id is required for PricingCatalog import" if team_id.blank?
    raise ArgumentError, "source_key is required for PricingCatalog import" if source_key.blank?

    batch = []
    batch_size = 1000
    total_rows = 0
    headers = nil
    category ||= detect_category_from_source_key(source_key)
    validate_category!(category, source_key: source_key, team_id: team_id)

    parsed_file.sheets.each do |sheet|
      parsed_file.default_sheet = sheet

      parsed_file.each_with_index do |row, i|
        if i.zero?
          headers = build_headers(row, team_id)
        else
          batch << row
          total_rows += 1
        end

        if batch.size >= batch_size
          PricingCatalogImportJob.perform_now(batch.dup, category, headers, team_id)
          batch = []
        end
      end
    end

    PricingCatalogImportJob.perform_now(batch, category, headers, team_id) if batch.present?

    total_rows
  end

  def self.build_headers(row, team_id = nil)
    header_mappings = normalized_header_aliases_for_pricing_catalog(team_id)
    valid_columns = column_names.to_set
    headers = {}
    row.each_with_index do |x, i|
      next if x.nil? || x.strip == ""
      normalized_header = normalize_header_key(x)
      # If the incoming header is already a canonical PricingCatalog column,
      # do not alias it again (prevents double-mapping on processed files).
      mapped_header =
        if valid_columns.include?(normalized_header)
          normalized_header
        else
          header_mappings[normalized_header] || normalized_header
        end
      mapped_header = normalize_header_key(mapped_header)
      next unless valid_columns.include?(mapped_header)
      headers[mapped_header] = i
    end

    required_headers = required_headers_for_pricing_catalog(team_id)
    missing_headers = required_headers - headers.keys.map(&:to_s)
    if missing_headers.any?
      Rails.logger.warn(
        "[PricingCatalog] Missing mapped headers for team_id=#{team_id}: #{missing_headers.join(', ')}. " \
        "Continuing with available headers: #{headers.keys.join(', ')}"
      )
    end

    headers
  end

  def self.detect_category_from_source_key(source_key)
    name = source_key.to_s.downcase
    return "340B" if name.include?("340b")
    return "GPO"  if name.include?("gpo")
    return "WAC"  if name.include?("wac")
    "Unknown"
  end

  def self.validate_category!(category, source_key:, team_id:)
    return unless category.to_s.casecmp("Unknown").zero?

    NotificationMailer.pricing_catalog_category_not_found_notification(
      file_name: source_key.to_s,
      team_id: team_id.to_s
    ).deliver_now

    raise "Category detection failed for file #{source_key} and team #{team_id}"
  end

  def self.expected_headers
    %w[
      ndc_code material_number_numeric generic_name trade_name strength form material_size contract_name buying_group
      buying_group_name hcpc_code uoi_cost vendor_name material_group ahfs_num ahfs_desc cardinal_ahfs
      material_description ndc_with_dash pack_quantity_d pack_size_qty spd_indicator packing_indicator_unit_dose
      unit_of_measure unit_of_sale effective_start_date current_catalog_price status
    ]
  end

  def self.required_headers_for_pricing_catalog(team_id)
    rules = RuleEngine.where(team_id: team_id).last&.header_rules
    pricing_catalog_rules = rules.is_a?(Hash) ? rules["pricing_catalog"] : nil
    required = Array(pricing_catalog_rules).map { |h| normalize_header_key(h) }.reject(&:empty?)
    return required if required.any?

    expected_headers
  end

  def self.normalized_header_aliases_for_pricing_catalog(team_id)
    legacy_aliases = {"NDC 11"=>"ndc_code",
    "Unit of Measure"=>"unit_of_sale",
    "Packing Indicator"=>"packing_indicator_unit_dose",
    "Base Unit of Measure"=>"unit_of_measure",
    "Material Number (Numeric)"=>"material_number_numeric",
    "Packing Indicator (Unit Dose)"=>"packing_indicator_unit_dose"}

    rule_aliases_raw = RuleEngine.where(team_id: team_id).last&.header_aliases
    pricing_catalog_aliases = rule_aliases_raw.is_a?(Hash) ? rule_aliases_raw["pricing_catalog"] : nil

    normalized_rule_aliases =
      if pricing_catalog_aliases.is_a?(Hash)
        pricing_catalog_aliases.each_with_object({}) do |(source, target), acc|
          next if source.blank? || target.blank?
          source_key = normalize_header_key(source)
          acc[source_key] = normalize_header_key(target)
        end
      else
        {}
      end

    legacy_aliases.merge(normalized_rule_aliases)
  end

  def self.normalize_header_key(value)
    value.to_s.strip.downcase.scan(/[a-z0-9]+/).join("_")
  end
end
