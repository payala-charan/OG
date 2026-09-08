# frozen_string_literal: true

module InsurancePreference
  class BiosimilarParser
    HEADER_ALIASES = {
      generic_name: ["generic name", "generic_name"],
      insurances: ["insurances", "insurance"],
      new_insurances: ["new insurances", "new insurance", "new_insurance", "new_insurances"],
      hcpcs_code: ["hcpcs code", "hcpcs_code", "hcpcs"],
      generic_name_group: ["generic name group", "generic_name_group"],
      status: ["status"]
    }.freeze

    SheetResult = Struct.new(
      :name,
      :header_row,
      :columns,
      :rows,
      :group_column_missing,
      :has_new_insurances,
      :insert_after_column,
      keyword_init: true
    )
    RowResult = Struct.new(
      :sheet_name,
      :source_row_number,
      :generic_name,
      :generic_name_group,
      :generic_name_group_inferred,
      :hcpcs_code,
      :status_flag,
      :source_column_used,
      :actual_insurances,
      :actual_text,
      :no_data,
      keyword_init: true
    )
    ParseResult = Struct.new(:sheets, :warnings, keyword_init: true)

    def initialize(path)
      @path = path
    end

    def call
      book = Roo::Spreadsheet.open(@path)
      sheets = []
      warnings = []

      book.sheets.each do |sheet_name|
        sheet = book.sheet(sheet_name)
        parsed = parse_sheet(sheet_name, sheet)
        next unless parsed

        sheets << parsed
        if parsed.group_column_missing
          warnings << "Tab '#{sheet_name}' has no Generic Name Group column — groups were inferred from generic names"
        end
      end

      ParseResult.new(sheets: sheets, warnings: warnings)
    ensure
      book&.close
    end

    private

    def parse_sheet(name, sheet)
      header_row, mapping = detect_headers(sheet)
      return nil unless mapping[:generic_name]

      group_missing = mapping[:generic_name_group].nil?
      rows = []

      ((header_row + 1)..sheet.last_row.to_i).each do |ridx|
        generic_name = Text.collapse_ws(cell(sheet, ridx, mapping[:generic_name]))
        next if generic_name.empty?

        group_raw = mapping[:generic_name_group] ? Text.collapse_ws(cell(sheet, ridx, mapping[:generic_name_group])) : ""
        inferred = false
        group = group_raw
        if group.empty?
          group = GroupInference.infer(generic_name).to_s
          inferred = group.present?
        end

        new_text = mapping[:new_insurances] ? Text.collapse_ws(cell(sheet, ridx, mapping[:new_insurances])) : ""
        old_text = mapping[:insurances] ? Text.collapse_ws(cell(sheet, ridx, mapping[:insurances])) : ""
        source_col, actual_text = if new_text.present?
          ["New Insurances", new_text]
        elsif old_text.present?
          ["Insurances", old_text]
        else
          [nil, ""]
        end

        rows << RowResult.new(
          sheet_name: name,
          source_row_number: ridx,
          generic_name: generic_name,
          generic_name_group: group.presence,
          generic_name_group_inferred: inferred,
          hcpcs_code: mapping[:hcpcs_code] ? Text.collapse_ws(cell(sheet, ridx, mapping[:hcpcs_code])) : nil,
          status_flag: mapping[:status] ? Text.collapse_ws(cell(sheet, ridx, mapping[:status])) : nil,
          source_column_used: source_col,
          actual_insurances: Text.split_plan_names(actual_text),
          actual_text: actual_text,
          no_data: actual_text.blank?
        )
      end

      return nil if rows.empty?

      insert_after = mapping[:new_insurances] || mapping[:insurances]
      SheetResult.new(
        name: name,
        header_row: header_row,
        columns: mapping,
        rows: rows,
        group_column_missing: group_missing,
        has_new_insurances: mapping[:new_insurances].present?,
        insert_after_column: insert_after
      )
    end

    def detect_headers(sheet)
      max_scan = [sheet.last_row.to_i, 10].min
      (1..max_scan).each do |ridx|
        values = (1..sheet.last_column.to_i).map { |cidx| [cidx, Text.header_key(cell(sheet, ridx, cidx))] }
        mapping = {}
        HEADER_ALIASES.each do |field, aliases|
          hit = values.find { |_cidx, key| aliases.include?(key) }
          mapping[field] = hit&.first
        end
        return [ridx, mapping] if mapping[:generic_name]
      end
      [nil, {}]
    end

    def cell(sheet, row, col)
      return nil unless col

      sheet.cell(row, col)
    end
  end
end
