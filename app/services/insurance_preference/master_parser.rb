# frozen_string_literal: true

require "set"

module InsurancePreference
  class MasterParser
    BrandColumn = Struct.new(:raw_header, :core, :code, :identity, keyword_init: true)
    TabResult = Struct.new(:name, :columns, :required_by_identity, keyword_init: true)
    ParseResult = Struct.new(:tabs, :skipped_tabs, keyword_init: true)

    def initialize(path)
      @path = path
    end

    def call
      book = Roo::Spreadsheet.open(@path)
      tabs = []
      skipped = []

      book.sheets.each do |sheet_name|
        sheet = book.sheet(sheet_name)
        if drug_group_tab?(sheet)
          tabs << parse_tab(sheet_name, sheet)
        else
          skipped << sheet_name
        end
      end

      ParseResult.new(tabs: tabs, skipped_tabs: skipped)
    ensure
      book&.close
    end

    def self.parse_header(raw)
      text = Text.strip_leading_rank(raw)
      code = Text.hcpcs_code(text)
      without_code = code ? text.sub(/#{Regexp.escape(code)}\s*\z/i, "").strip : text
      core = if (m = without_code.match(/\(([^)]+)\)/))
        Text.collapse_ws(m[1])
      else
        Text.collapse_ws(without_code)
      end
      BrandColumn.new(
        raw_header: Text.collapse_ws(raw),
        core: core,
        code: code,
        identity: [Text.exact_key(core), code.to_s.upcase]
      )
    end

    private

    def drug_group_tab?(sheet)
      (1..sheet.last_row.to_i).any? do |row|
        Text.collapse_ws(sheet.cell(row, 1)).start_with?("Insurance -")
      end
    end

    def parse_tab(name, sheet)
      columns_by_identity = {}
      required_by_identity = Hash.new { |h, k| h[k] = Set.new }
      last_row = sheet.last_row.to_i
      row = 1

      while row <= last_row
        cell_a = Text.collapse_ws(sheet.cell(row, 1))
        unless cell_a.start_with?("Insurance -")
          row += 1
          next
        end

        header_row = row
        headers = extract_headers(sheet, header_row)
        headers.each { |col| columns_by_identity[col.identity] ||= col }

        row = header_row + 1
        while row <= last_row
          plan_text = Text.collapse_ws(sheet.cell(row, 1))
          break if plan_text.empty? || plan_text.start_with?("Insurance -")

          plans = Text.split_plan_names(plan_text)
          headers.each do |col|
            value = Text.collapse_ws(sheet.cell(row, col_index_for(sheet, header_row, col))).upcase
            next unless value == "Y"

            plans.each { |plan| required_by_identity[col.identity] << plan }
          end
          row += 1
        end
      end

      TabResult.new(
        name: name,
        columns: columns_by_identity.values,
        required_by_identity: required_by_identity.transform_values(&:to_a)
      )
    end

    def extract_headers(sheet, header_row)
      headers = []
      col = 2
      last_col = sheet.last_column.to_i
      while col <= last_col
        raw = Text.collapse_ws(sheet.cell(header_row, col))
        break if raw.casecmp("Hyperlink").zero?
        headers << self.class.parse_header(raw) if raw.present?
        col += 1
      end
      headers.each_with_index { |h, idx| h.define_singleton_method(:col_offset) { idx } }
      @header_cols = headers.each_with_index.to_h { |h, idx| [h.identity, idx + 2] }
      headers
    end

    def col_index_for(_sheet, _header_row, col)
      @header_cols[col.identity]
    end
  end
end
