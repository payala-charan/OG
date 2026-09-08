class PricingCatalogsController < ApplicationController
  require 'roo'
  require 'csv'

  before_action :load_available_files, only: [:index, :mapping, :results]
  before_action :load_selected_file_name, only: [:index, :mapping, :process_mapping, :results, :download]

  def index
  end

  def create
    if params[:file].blank? || params[:ndc_codes].blank?
      flash[:alert] = "Please provide both an Excel file and NDC codes."
      redirect_to pricing_catalogs_path and return
    end

    file = params[:file]
    file_name = normalize_file_name(file.original_filename)
    session[:current_pricing_file_name] = file_name
    session[:extracted_headers] = []

    begin
      ExcelRecord.where(file_name: file_name).destroy_all
      NdcCode.where(file_name: file_name).destroy_all
      NdcResult.where(file_name: file_name).destroy_all

      codes = params[:ndc_codes].split(/\r?\n/).map(&:strip).reject(&:empty?)
      codes.each do |code|
        NdcCode.create!(code: code, file_name: file_name)
      end

      spreadsheet = Roo::Spreadsheet.open(file.path)
      headers = spreadsheet.row(1).map(&:to_s).map(&:strip)
      session[:extracted_headers] = headers

      (2..spreadsheet.last_row).each do |i|
        row = spreadsheet.row(i)
        data_hash = Hash[headers.zip(row)]
        ExcelRecord.create!(data: data_hash, file_name: file_name)
      end

      redirect_to mapping_pricing_catalogs_path(file_name: file_name)
    rescue => e
      flash[:alert] = "Error processing upload: #{e.message}"
      redirect_to pricing_catalogs_path
    end
  end

  def mapping
    @file_name = @selected_file_name
    @headers = if params[:file_name].present?
      file_headers_for(@file_name)
    else
      session[:extracted_headers] || []
    end

    if @headers.empty?
      flash[:alert] = "No headers found for #{ @file_name.present? ? @file_name : 'the selected file' }. Please upload again."
      redirect_to pricing_catalogs_path and return
    end

    session[:extracted_headers] = @headers
  end

  def process_mapping
    @col1 = params[:column_1]
    @col2 = params[:column_2]
    @operator = params[:operator]
    @selector = params[:selector]
    file_name = @selected_file_name

    if @col1.blank? || @col2.blank? || @operator.blank? || @selector.blank?
      flash[:alert] = "Please fill out all mapping fields."
      redirect_to mapping_pricing_catalogs_path(file_name: file_name) and return
    end

    if file_name.blank?
      flash[:alert] = "Missing file selection. Please choose a file to continue."
      redirect_to pricing_catalogs_path and return
    end

    ndc_codes = params[:ndc_codes].present? ? params[:ndc_codes].split(/\r?\n/).map(&:strip).reject(&:empty?) : NdcCode.where(file_name: file_name).pluck(:code)
    NdcCode.where(file_name: file_name).destroy_all
    NdcResult.where(file_name: file_name).destroy_all
    ndc_codes.each do |code|
      NdcCode.create!(code: code, file_name: file_name)
    end

    ndc_codes.each do |ndc|
      matching_records = ExcelRecord.where(file_name: file_name).where("data ->> ? = ?", @selector, ndc)

      if matching_records.empty? && ndc.match?(/\A\d+\z/)
        numeric_ndc = ndc.to_i.to_f.to_s
        matching_records = ExcelRecord.where(file_name: file_name).where("data ->> ? = ?", @selector, numeric_ndc)
      end

      if matching_records.empty?
        NdcResult.create!(ndc_code: ndc, result_value: 0.0, file_name: file_name)
      else
        calculated_values = matching_records.map do |record|
          val1 = record.data[@col1].to_s.gsub(/[\$,%]/, '').strip.to_f rescue 0.0
          val2 = record.data[@col2].to_s.gsub(/[\$,%]/, '').strip.to_f rescue 0.0
          compute_value(val1, val2, @operator)
        end
        min_value = calculated_values.min
        NdcResult.create!(ndc_code: ndc, result_value: min_value.round(2), file_name: file_name)
      end
    end

    redirect_to results_pricing_catalogs_path(file_name: file_name)
  end

  def results
    @file_name = @selected_file_name
    @results = @file_name.present? ? NdcResult.where(file_name: @file_name) : NdcResult.none
  end

  def download
    @file_name = @selected_file_name
    @results = @file_name.present? ? NdcResult.where(file_name: @file_name) : NdcResult.none

    csv_data = CSV.generate(headers: true) do |csv|
      csv << ["File", "NDC Code", "Result Value"]
      @results.each do |result|
        csv << [@file_name, result.ndc_code, result.result_value]
      end
    end

    send_data csv_data, filename: "pricing_catalog_results_#{@file_name.to_s.parameterize}_#{Date.today}.csv", type: "text/csv"
  end

  private

  def compute_value(val1, val2, op)
    case op
    when '+' then val1 + val2
    when '-' then val1 - val2
    when '*' then val1 * val2
    when '/'
      return 0.0 if val2.zero?
      val1 / val2
    else
      0.0
    end
  end

  def file_headers_for(file_name)
    record = ExcelRecord.where(file_name: file_name).limit(1).pluck(:data).first
    record.present? ? record.keys : []
  end

  def load_available_files
    @available_files = ExcelRecord.order(created_at: :desc).pluck(:file_name).uniq.compact
  end

  def load_selected_file_name
    @selected_file_name = params[:file_name].presence || session[:current_pricing_file_name]
    session[:current_pricing_file_name] = @selected_file_name if @selected_file_name.present?
  end

  def normalize_file_name(file_name)
    File.basename(file_name.to_s)
  end
end
