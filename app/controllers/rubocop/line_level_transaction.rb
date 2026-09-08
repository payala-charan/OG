# frozen_string_literal: true

class LineLevelTransaction < ApplicationRecord

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

  def self.process_file(parsed_file, team_id: nil, source_key: nil)
    batch = []
    batch_size = 1000
    total_rows = 0
    all_sheets = parsed_file.sheets
    all_sheets.each do |sheet|
      parsed_file.default_sheet = sheet
      parsed_file.each_with_index do |row, i|
        if i.zero?
          build_headers(row)
        else
          batch << row
        end
        if batch.size >= batch_size
          process_row(batch, team_id)
          batch = []
        end
        total_rows = i
      end
    end
    process_row(batch, team_id)
    total_rows
  end

  def self.build_headers(row)
    headers = {}

    row.each_with_index do |x, i|
    normalized_header = x.to_s.strip.downcase.scan(/[a-z0-9]+/).join("_")
    headers[normalized_header] = i
  end

    missing_headers = expected_headers - headers.keys
    raise "Missing required header entry '#{missing_headers[0]}'" unless missing_headers.empty?

    headers
  end

  def self.expected_headers
    %w[hospital_acct_num encounter_number patient_mrn service_date procedure_code procedure_desc
       billed_amount paid_amount copay coinsurance department_name revenue_code primary_payor secondary_payor]
  end

  def self.process_row(batch, team_id)
    return unless batch.present?

    LineLevelTransactionImportJob.perform_now(batch, team_id)
  end
end
