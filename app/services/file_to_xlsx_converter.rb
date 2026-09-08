require 'csv'
require 'axlsx'
require 'pdf-reader'
require 'docx'

class FileToXlsxConverter
  attr_reader :input_path, :output_path, :original_filename

  def initialize(input_path:, output_path:, original_filename:)
    @input_path = input_path
    @output_path = output_path
    @original_filename = original_filename
  end

  def call
    raise "File not found: #{input_path}" unless File.exist?(input_path)

    rows = parse_file
    raise "No data found or unsupported format" if rows.empty?

    write_xlsx(rows)

    puts "✅ Successfully converted:"
    puts "📄 #{original_filename}"
    puts "➡️ #{output_path}"
  end

  private

  def parse_file
    ext = File.extname(original_filename).downcase
    case ext
    when '.csv', '.txt'
      parse_csv_or_txt
    when '.pdf'
      parse_pdf
    when '.docx', '.doc'
      parse_docx
    else
      # Fallback: try to read line by line
      parse_generic_text
    end
  end

  def parse_csv_or_txt
    rows = []
    # Try to detect if it's pipe-separated or comma-separated
    first_line = File.open(input_path, &:readline) rescue ""
    col_sep = first_line.include?("|") ? "|" : (first_line.include?(",") ? "," : "\t")
    
    # Try to read as CSV. If that fails, fallback to line by line.
    begin
      CSV.foreach(input_path, col_sep: col_sep, headers: true, encoding: "bom|utf-8") do |row|
        if rows.empty? && row.headers
          rows << row.headers
        end
        rows << row.fields
      end
    rescue CSV::MalformedCSVError, ArgumentError => e
      Rails.logger.warn("CSV parsing failed, falling back to raw text: #{e.message}")
      return parse_generic_text
    end
    
    # If no headers detected or just raw txt with no col_sep
    if rows.empty?
      return parse_generic_text
    end
    
    rows
  end

  def parse_pdf
    rows = []
    reader = PDF::Reader.new(input_path)
    reader.pages.each do |page|
      text = page.text
      text.split("\n").each do |line|
        stripped = line.strip
        rows << [stripped] unless stripped.empty?
      end
    end
    rows
  end

  def parse_docx
    rows = []
    begin
      doc = Docx::Document.open(input_path)
      doc.paragraphs.each do |p|
        stripped = p.text.strip
        rows << [stripped] unless stripped.empty?
      end
    rescue => e
      Rails.logger.warn("Docx parsing failed, falling back to raw text: #{e.message}")
      return parse_generic_text
    end
    rows
  end

  def parse_generic_text
    rows = []
    File.foreach(input_path, encoding: "bom|utf-8") do |line|
      stripped = line.strip
      rows << [stripped] unless stripped.empty?
    rescue ArgumentError => e
      # Ignore encoding issues on individual lines
      next
    end
    rows
  end

  def write_xlsx(rows)
    package = Axlsx::Package.new
    workbook = package.workbook

    workbook.add_worksheet(name: "Converted Data") do |sheet|
      rows.each_with_index do |row, index|
        if index == 0
          # Header row (bold)
          sheet.add_row row, style: header_style(workbook)
        else
          sheet.add_row row
        end
      end
    end

    package.serialize(output_path)
  end

  def header_style(workbook)
    workbook.styles.add_style(b: true)
  end
end
