# frozen_string_literal: true
class BiosimilarPrice < ApplicationRecord
  # has_paper_trail
  belongs_to :accounting_period
  belongs_to :reimbursement
  has_many :product_rankings, dependent: :destroy
  attr_accessor :skip_recalculation_callback
  after_initialize do
    self.skip_recalculation_callback ||= false
  end
  after_commit :enqueue_conversion_recalculation,
               on: :update,
               if: :pricing_changed?
  OUTPATIENT = ["Outpatient", "Emergency"]
  INPATIENT = "Inpatient"
  TEAM_ID = ["198"]
  COMBINED_GROUPS = ["HYALURONATE SODIUM", "LEUPROLIDE ACETATE", "DENOSUMAB", "BENDAMUSTINE", "INFLIXIMAB", "PEGFILGRASTIM"]

  # NDC Match + NdcMatchCheckJob: collect 11-digit normalized keys from ndc_code, alternate_ndc_code,
  # and delimiter-separated other_ndc_codes. Scoped to team only (any quarter), matching prior behavior.
  OTHER_NDC_SPLIT = /[,\n;|]+/

  # Single canonical form for comparing utilization NDCs to biosimilar columns (handles spaces, parens, dots).
  def self.normalize_ndc_for_match(ndc)
    digits = ndc.to_s.gsub(/\D/, "")
    return nil if digits.blank?

    digits = digits[-11..] if digits.length > 11
    digits.rjust(11, "0")
  end

  def self.normalized_ndc_key_set_for_team(team_id)
    keys = Set.new
    where(team_id: team_id.to_s)
      .pluck(:ndc_code, :alternate_ndc_code, :other_ndc_codes)
      .each do |ndc_code, alternate_ndc_code, other_ndc_codes|
        [ndc_code, alternate_ndc_code].each do |raw|
          next if raw.blank?

          k = normalize_ndc_for_match(raw)
          keys << k if k.present?
        end
        next if other_ndc_codes.blank?

        other_ndc_codes.to_s.split(OTHER_NDC_SPLIT).each do |part|
          part = part.strip
          next if part.blank?

          k = normalize_ndc_for_match(part)
          keys << k if k.present?
        end
      end
    keys
  end

  # E.g. QuarterPullCmsTotalUnitsJob: +biosimilar_scope+ is typically +ur.biosimilars+ (team, quarter, status,
  # generic group). Resolves NDC, alternate, and any delimiter-separated token in +other_ndc_codes+ (commas, etc.),
  # using the same normalization and splitting as +normalized_ndc_key_set_for_team+.
  def self.first_matching_biosimilar_for_utilization_ndc(biosimilar_scope, raw_utilization_ndc)
    key = normalize_ndc_for_match(raw_utilization_ndc)
    return nil if key.blank?

    found = nil
    biosimilar_scope.find_each do |b|
      if biosimilar_row_matches_ndc_key?(b, key)
        found = b
        break
      end
    end
    found
  end

  def self.biosimilar_row_matches_ndc_key?(biosimilar, normalized_key)
    [biosimilar.ndc_code, biosimilar.alternate_ndc_code].each do |raw|
      next if raw.blank?

      k = normalize_ndc_for_match(raw)
      return true if k == normalized_key
    end
    return false if biosimilar.other_ndc_codes.blank?

    # other_ndc_codes: one NDC as a single string, or several split by comma only (e.g. "a,b").
    biosimilar.other_ndc_codes.to_s.split(",").each do |part|
      part = part.strip
      next if part.blank?

      k = normalize_ndc_for_match(part)
      return true if k == normalized_key
    end
    false
  end

  def self.normalize_ndc_segment(ndc)
    normalize_ndc_for_match(ndc).to_s
  end

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
  IGNORED_IMPORT_HEADERS = %w[cms_margin_per_unit_three_forty_b_cost].freeze

  def self.ignored_column_indexes_from_headers(headers_map)
    IGNORED_IMPORT_HEADERS.filter_map { |name| headers_map[name] }.uniq
  end

  def self.process_file(parsed_file, team_id: nil, source_key: nil)

    batch_size = 1000
    total_rows = 0
    all_sheets = parsed_file.sheets
    all_sheets.each do |sheet|
      parsed_file.default_sheet = sheet
      batch = []
      ignored_indexes = []
      parsed_file.each_with_index do |row, i|
        if i.zero?
          headers_map = build_headers(row)
          ignored_indexes = ignored_column_indexes_from_headers(headers_map)
        else
          row[0] = clean_html(row[0]) if row[0].is_a?(String)
          batch << row
        end
        if batch.size >= batch_size
          process_row(batch, ignored_indexes)
          batch = []
        end
        total_rows = i
      end
      process_row(batch, ignored_indexes) if batch.present?
    end
    total_rows
  end

  def self.export_header_aliases
    {
      "blended_340b_cost" => "blended_cost_three_forty_b",
      "cms_margin_340b_cost" => "cms_margin_three_forty_b_cost",
      "blended_340b_margin" => "blended_cms_margin_three_forty_b_cost",
      "blended_percent_margin" => "blended_cms_percent_margin",
      "blended_gpo_margin" => "blended_cms_margin_gpo_cost"
    }.freeze
  end

  def self.build_headers(row)
    headers = {}

    row.each_with_index do |header, index|
      normalized_header = header.to_s.strip.downcase.scan(/[a-z0-9]+/).join("_")
      headers[normalized_header] = index
    end

    export_header_aliases.each do |export_name, canonical_name|
      next if headers.key?(canonical_name)
      next unless headers.key?(export_name)

      headers[canonical_name] = headers[export_name]
    end

    missing_headers = expected_headers - headers.keys

    raise "Missing required header entry '#{missing_headers[0]}'" unless missing_headers.empty?

    headers
  end

  def self.expected_headers
    %w[
      generic_name match ndc_code alternate_ndc_code other_ndc_codes insurances hcpcs_code billing_unit
      reimbursement_per_billing_unit billing_unit_per_package_size cms_reimbursement_per_package
      cost_three_forty_b cost_per_unit_three_forty_b blended_cost_three_forty_b cms_margin_three_forty_b_cost
      blended_cms_margin_three_forty_b_cost cms_percent_margin blended_cms_percent_margin gpo_cost blended_gpo_cost cms_margin_gpo_cost blended_cms_margin_gpo_cost
      gpo_percent_margin blended_gpo_percent_margin accounting_period_id reimbursement_id generic_name_group status team_id
    ]
  end

  def self.process_row(batch, ignored_column_indexes = [])
    return unless batch.present?

    BiosimilarPriceImportJob.perform_now(batch, ignored_column_indexes)
  end

  def self.clean_html(html_string)
    Nokogiri::HTML(html_string).text.strip
  end

  def self.extract_brand_and_strength
    BiosimilarPrice.where(accounting_period_id: 6, status: nil).each do |record|
      extracted_brand = record.generic_name.scan(/\(([^)]+)\)/).flatten.first
      extracted_strength = record.generic_name.scan(/\b\d+(?:\.\d+)?\s?[a-zA-Z]+(?:\/\d+(?:\.\d+)?\s?[a-zA-Z]+)?\b/)
      final_strength = extracted_strength.join(" ").gsub(/\s+/, "").upcase
      record.update(extracted_brand_name: extracted_brand.upcase, extracted_strength: final_strength) if extracted_brand.present?
    end
  end
  
  def self.find_conversion(original_invoice, product_name)
      where(reimbursement: original_invoice.reimbursement, status: nil)
      .where("LOWER(generic_name) = ?", product_name.downcase)
      .first
  end

  def enqueue_conversion_recalculation
    pending_jobs = []
    if saved_change_to_cost_three_forty_b?
      ndc = self.ndc_code.presence || self.alternate_ndc_code.presence || self.other_ndc_codes
      recalculate_utilization_reports(self.accounting_period_id, ndc, self.generic_name, self.generic_name_group, self.cost_three_forty_b, OUTPATIENT)

      cms_margin_cost_per_unit_340b = self.cost_three_forty_b / self.billing_unit_per_package_size
      cms_margin_340b_cost = self.cms_reimbursement_per_package - self.cost_three_forty_b
      cms_percent_margin = (cms_margin_340b_cost / self.cost_three_forty_b) * 100
      update_columns(
        cost_per_unit_three_forty_b: cms_margin_cost_per_unit_340b.round(2),
        cms_margin_three_forty_b_cost: cms_margin_340b_cost.round(2),
        cms_percent_margin: cms_percent_margin.round(2)
      )
    end

    if saved_change_to_gpo_cost?
      recalculate_utilization_reports(self.accounting_period_id, self.ndc_code, self.generic_name, self.generic_name_group, self.gpo_cost, INPATIENT)

      cms_reimbursement = BiosimilarPrice.where(accounting_period_id: self.accounting_period_id, ndc_code: self.ndc_code)
                                         .pluck(:cms_reimbursement_per_package).first
      cms_margin_gpo_cost = cms_reimbursement - self.gpo_cost
      gpo_percent_margin = (cms_margin_gpo_cost / self.gpo_cost) * 100
      update_columns(
        cms_margin_gpo_cost: cms_margin_gpo_cost.round(2),
        gpo_percent_margin: gpo_percent_margin.round(2)
      )
    end

    histories = UtilizationHistory.where(accounting_period_id: self.accounting_period_id,
                                         generic_name_group: self.generic_name_group.capitalize)
    histories.each do |history|
      filtered_versions = history.versions.map do |version|
        if version["ndcCode"] == self.ndc_code
          total_units = version["totalUnits"].to_f.round(2)
          if version["chargeClass"] == "Inpatient"
            total_product_cost = total_units * self.gpo_cost.to_f.round(2)
            price = self.gpo_cost.to_f.round(2)
          else
            total_product_cost = total_units * self.cost_three_forty_b.to_f.round(2)
            price = self.cost_three_forty_b.to_f.round(2)
          end
          total_margin = version["insuranceValue"].to_f.round(2) - (price * total_units)
          percent_margin = (total_margin / (price * total_units)) * 100.0
          version.merge!(
            "priceWithoutCostDistMinus" => price,
            "costDoseValue" => total_product_cost,
            "marginDoseValue" => total_margin.round(2),
            "percentMarginValue" => percent_margin.round(2)
          )
        end
        version
      end
      history.update(versions: filtered_versions)
      UtilizationHistoryConversionsBatchJob.perform_now(history.id, 100, filtered_versions,
                                                        self.generic_name_group.capitalize,
                                                        self.accounting_period_id,
                                                        history.version_name, pending_jobs)
    end
  end

  def calculate_percent_margins
    BiosimilarPrice.where(accounting_period_id: 6, status: nil).all.each do |biosimilar_price|
      if biosimilar_price.cost_three_forty_b.present?
        cms_percent_margin = (biosimilar_price.cms_margin_three_forty_b_cost / biosimilar_price.cost_three_forty_b) * 100
        gpo_percent_margin = (biosimilar_price.cms_margin_gpo_cost / biosimilar_price.gpo_cost) * 100
        biosimilar_price.update(cms_percent_margin: cms_percent_margin.round(2), gpo_percent_margin: gpo_percent_margin.round(2))
      end
    end
  end

  def calculate_blended_percent_margins
    BiosimilarPrice.where(accounting_period_id: 6, status: nil).all.each do |biosimilar_price|
      if biosimilar_price.cost_three_forty_b.present?
        cms_percent_margin = (biosimilar_price.cms_margin_three_forty_b_cost / biosimilar_price.cost_three_forty_b) * 100
        gpo_percent_margin = (biosimilar_price.cms_margin_gpo_cost / biosimilar_price.gpo_cost) * 100
        biosimilar_price.update(cms_percent_margin: cms_percent_margin.round(2), gpo_percent_margin: gpo_percent_margin.round(2))
      end
    end
  end

  def self.calculate_blended_costs
    all_generic_name_groups =BiosimilarPrice.where(team_id: TEAM_ID, status: nil).where.not(generic_name_group: ["DENOSUMAB", "HYALURONATE SODIUM"]).pluck(:generic_name_group).uniq
    all_generic_name_groups.each do |generic_name_group|
      strength_total_units = {}
      missing_records = []     
      biosimilar_records =BiosimilarPrice.where(accounting_period_id: 6, status: nil, generic_name_group: generic_name_group,team_id: TEAM_ID)
      biosimilar_records.each do |biosimilar|
        group_name = biosimilar.generic_name_group
        all_utilization_reports =UtilizationReport.joins(:ndc_code_record).where(team_id: TEAM_ID, accounting_period_id: 6, category: nil, generic_name_group: group_name.capitalize, charge_class: OUTPATIENT)
        total_units = all_utilization_reports.sum(:total_units).to_f
        all_extracted_strengths =biosimilar_records.where(generic_name_group: group_name, extracted_brand_name: biosimilar.extracted_brand_name).pluck(:extracted_strength).uniq
        numerator_strengths = all_extracted_strengths.compact.map { |s| s.split('/').first }.uniq
        total_blended_cost = 0
        total_blended_cms_margin_three_forty_b_cost = 0
        total_blended_gpo_cost = 0
        total_blended_cms_margin_gpo_cost = 0
        blended_cms_percent_margin = 0
        blended_gpo_percent_margin = 0
        if numerator_strengths.size == 1 || COMBINED_GROUPS.include?(group_name)
         biosilimar_ndc_codes=biosimilar.ndc_code.presence || biosimilar.alternate_ndc_code.presence || biosimilar.other_ndc_codes
         corresponding_total_units=0
         corresponding_total_units=all_utilization_reports.where(ndc_code_record: { ndc_code: biosilimar_ndc_codes }).sum(:total_units).to_f
         total_units=corresponding_total_units/total_units
         total_blended_cost = biosimilar.cost_three_forty_b.to_f
         total_blended_cms_margin_three_forty_b_cost = biosimilar.cms_margin_three_forty_b_cost.to_f
         total_blended_gpo_cost = biosimilar.gpo_cost.to_f
         total_blended_cms_margin_gpo_cost = biosimilar.cms_margin_gpo_cost.to_f
         blended_cms_percent_margin = total_blended_cost > 0 ? (total_blended_cms_margin_three_forty_b_cost / total_blended_cost * 100) : 0
         blended_gpo_percent_margin = total_blended_gpo_cost > 0 ? (total_blended_cms_margin_gpo_cost / total_blended_gpo_cost * 100) : 0
         biosimilar.update(
            blended_cost_three_forty_b: total_blended_cost,
            blended_cms_margin_three_forty_b_cost: total_blended_cms_margin_three_forty_b_cost,
            blended_cms_percent_margin: blended_cms_percent_margin,
            blended_gpo_cost: total_blended_gpo_cost,
            blended_cms_margin_gpo_cost: total_blended_cms_margin_gpo_cost,
            blended_gpo_percent_margin: blended_gpo_percent_margin
         )
        else
          numerator_strengths.each do |strength|
           next unless 
           biosimilar_record = biosimilar_records.where("extracted_strength LIKE ?", "#{strength}%").where(extracted_brand_name: biosimilar.extracted_brand_name).last
           biosilimar_ndc_codes = biosimilar_records.where("extracted_strength LIKE ?", "#{strength}%").pluck(:ndc_code, :alternate_ndc_code, :other_ndc_codes).flat_map { |codes| codes.compact }.uniq
           pckg_units = all_utilization_reports.where(ndc_code_record: { ndc_code: biosilimar_ndc_codes }).sum(:total_units).to_f
           if pckg_units != 0.0
            strength_total_units[strength] = pckg_units
           else
            missing_records << biosimilar_record.generic_name
           end
           ratio = total_units > 0 ? (pckg_units / total_units) : 0
           total_blended_cost += biosimilar_record.cost_three_forty_b.to_f * ratio
           total_blended_cms_margin_three_forty_b_cost += biosimilar_record.cms_margin_three_forty_b_cost.to_f * ratio
           total_blended_gpo_cost += biosimilar_record.gpo_cost.to_f * ratio
           total_blended_cms_margin_gpo_cost += biosimilar_record.cms_margin_gpo_cost.to_f * ratio

           blended_cms_percent_margin += total_blended_cost > 0 ? (total_blended_cms_margin_three_forty_b_cost / total_blended_cost * 100) : 0
           blended_gpo_percent_margin += total_blended_gpo_cost > 0 ? (total_blended_cms_margin_gpo_cost / total_blended_gpo_cost * 100) : 0

            biosimilar.update(
              blended_cost_three_forty_b: total_blended_cost,
              blended_cms_margin_three_forty_b_cost: total_blended_cms_margin_three_forty_b_cost,
              blended_cms_percent_margin: blended_cms_percent_margin,
              blended_gpo_cost: total_blended_gpo_cost,
              blended_cms_margin_gpo_cost: total_blended_cms_margin_gpo_cost,
              blended_gpo_percent_margin: blended_gpo_percent_margin
            )
          end
          if missing_records.any?      
            missing_records.uniq!
            total_units = all_utilization_reports.sum(:total_units).to_f
            missing_records.each do |record_name|
              record_strength = record_name[/\d+MG\/\d+ML/i]&.upcase
              next unless record_strength
              pckg_units = strength_total_units[record_strength]
              next unless pckg_units && pckg_units > 0
              biosimilar_record = biosimilar_records.where(generic_name: record_name).last
              next unless biosimilar_record
              ratio = total_units > 0 ? (pckg_units / total_units) : 0
              total_blended_cost = biosimilar_record.cost_three_forty_b.to_f * ratio
              total_blended_cms_margin_three_forty_b_cost = biosimilar_record.cms_margin_three_forty_b_cost.to_f * ratio
              total_blended_gpo_cost = biosimilar_record.gpo_cost.to_f * ratio
              total_blended_cms_margin_gpo_cost = biosimilar_record.cms_margin_gpo_cost.to_f * ratio
              blended_cms_percent_margin = total_blended_cost > 0 ? (total_blended_cms_margin_three_forty_b_cost / total_blended_cost * 100) : 0
              blended_gpo_percent_margin = total_blended_gpo_cost > 0 ? (total_blended_cms_margin_gpo_cost / total_blended_gpo_cost * 100) : 0
              biosimilar_record.update(
                blended_cost_three_forty_b: total_blended_cost,
                blended_cms_margin_three_forty_b_cost: total_blended_cms_margin_three_forty_b_cost,
                blended_cms_percent_margin: blended_cms_percent_margin,
                blended_gpo_cost: total_blended_gpo_cost,
                blended_cms_margin_gpo_cost: total_blended_cms_margin_gpo_cost,
                blended_gpo_percent_margin: blended_gpo_percent_margin
              )
            end
          end
        end
      end 
    end
  end

  def sum_blended_details
    all_brands = BiosimilarPrice.where(accounting_period_id: 4, status: nil, generic_name_group: "PEGFILGRASTIM").pluck(:extracted_brand_name).uniq

    all_brands.each do |brand_name|
      data = BiosimilarPrice.where(accounting_period_id: 4, status: nil, extracted_brand_name: brand_name)


      total_blended_cost = data.pluck(:blended_cost_three_forty_b).sum
      total_blended_cms_margin_three_forty_b_cost = data.pluck(:blended_cms_margin_three_forty_b_cost).sum
      total_blended_gpo_cost = data.pluck(:blended_gpo_cost).sum
      total_blended_cms_margin_gpo_cost = data.pluck(:blended_cms_margin_gpo_cost).sum

      blended_cms_percent_margin = total_blended_cost.positive? ? ((total_blended_cms_margin_three_forty_b_cost / total_blended_cost) * 100) : 0
      blended_gpo_percent_margin = total_blended_gpo_cost.positive? ? ((total_blended_cms_margin_gpo_cost / total_blended_gpo_cost) * 100) : 0

      data.update(
        blended_cost_three_forty_b: total_blended_cost,
        blended_cms_margin_three_forty_b_cost: total_blended_cms_margin_three_forty_b_cost,
        blended_cms_percent_margin: blended_cms_percent_margin,
        blended_gpo_cost: total_blended_gpo_cost,
        blended_cms_margin_gpo_cost: total_blended_cms_margin_gpo_cost,
        blended_gpo_percent_margin: blended_gpo_percent_margin
      )
    end
  end

  private

  def pricing_changed?
    return false if skip_recalculation_callback == true
    saved_change_to_cost_three_forty_b? || saved_change_to_gpo_cost?
  end

 def recalculate_utilization_reports(accounting_period_id, ndc_code, generic_name, generic_name_group, cost_value, charge_class)
    query = UtilizationReport.where(accounting_period_id: accounting_period_id, category: nil, charge_class: charge_class)
                             .joins(:ndc_code_record)
                             .where(ndc_code_record: { ndc_code: ndc_code })

    query.update(price_without_cost_dist_minus: cost_value)

    UtilizationReport.where(id: query.pluck(:id)).each do |detail|
      total_cost = detail.price_without_cost_dist_minus.to_f.round(2) * detail.total_units.round(2)
      total_margin = detail.insurance_payment_per_dose.round(2) - total_cost
      percent_margin = (total_margin / total_cost) * 100.0
      detail.update(total_margin: total_margin, percent_margin: percent_margin)
    end

    query.pluck(:id).each do |id|
      UtilizationReportConversionsBatchJob.perform_later(id, 100,
                                                         generic_name_group.capitalize,
                                                         accounting_period_id,
                                                         "default_version")
    end
  end
end
