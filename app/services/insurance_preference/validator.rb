# frozen_string_literal: true

module InsurancePreference
  class Validator
    RowOutcome = Struct.new(
      :source_sheet_name,
      :source_row_number,
      :generic_name,
      :generic_name_group,
      :generic_name_group_inferred,
      :hcpcs_code,
      :status_flag,
      :master_tab,
      :matched_brand_column,
      :match_confidence,
      :match_method,
      :source_column_used,
      :required_count,
      :actual_count,
      :validation_status,
      :missing_insurances,
      :spelling_mismatches,
      :extra_insurances,
      :claude_insurances,
      :notes,
      :insert_after_column,
      :header_row,
      keyword_init: true
    )

    Result = Struct.new(:rows, :warnings, :sheet_annotations, :formula_warnings, keyword_init: true)

    def initialize(master_path:, biosimilar_path:)
      @master_path = master_path
      @biosimilar_path = biosimilar_path
    end

    def call
      master = MasterParser.new(@master_path).call
      biosimilar = BiosimilarParser.new(@biosimilar_path).call
      resolver = TabResolver.new(master.tabs)
      warnings = biosimilar.warnings.dup
      warnings << "Skipped Master tabs without Insurance - blocks: #{master.skipped_tabs.join(', ')}" if master.skipped_tabs.any?

      outcomes = []
      sheet_annotations = []

      biosimilar.sheets.each do |sheet|
        cells = []
        sheet.rows.each do |row|
          outcome = validate_row(row, resolver, sheet)
          outcomes << outcome
          cells << {
            "row" => row.source_row_number,
            "runs" => outcome.claude_insurances.map { |run| { "text" => run.text, "color" => run.color } }
          }
        end

        next unless sheet.insert_after_column

        sheet_annotations << {
          "name" => sheet.name,
          "insert_col" => sheet.insert_after_column + 1,
          "header_row" => sheet.header_row,
          "cells" => cells
        }
      end

      Result.new(
        rows: outcomes,
        warnings: warnings,
        sheet_annotations: sheet_annotations,
        formula_warnings: []
      )
    end

    private

    def validate_row(row, resolver, sheet)
      notes = []
      notes << "Group inferred from generic name" if row.generic_name_group_inferred

      if Text.blank?(row.generic_name_group)
        return blank_mapping_outcome(row, sheet, "NO_GROUP", "NO_GROUP_ASSIGNED", "No generic name group assigned")
      end

      tab = resolver.resolve(row.generic_name_group)
      unless tab
        return blank_mapping_outcome(row, sheet, "NO_TAB", "NO_MASTER_MAPPING", "No Master tab for #{row.generic_name_group}")
      end

      matcher = BrandMatcher.new(tab.columns)
      match = matcher.match(generic_name: row.generic_name, group: row.generic_name_group, tab_found: true)
      if %w[NO_MATCH NO_GROUP NO_TAB].include?(match.method)
        return blank_mapping_outcome(row, sheet, match.method, "NO_MASTER_MAPPING", match.notes, tab.name)
      end

      required = Array(tab.required_by_identity[match.brand.identity])
      comparison = InsuranceComparator.new(required, row.actual_insurances).call
      status = validation_status_for(row, comparison)
      spelling = comparison.variants.select { |variant| variant.kind == "typo" }.map do |variant|
        {
          "master" => variant.required,
          "sheet" => variant.actual,
          "kind" => variant.kind,
          "similarity" => variant.similarity
        }
      end

      notes << match.notes if match.notes.present?
      comparison.variants.each do |variant|
        next if variant.kind == "typo"

        notes << "#{variant.kind}: #{variant.required} ↔ #{variant.actual}"
      end

      runs = if %w[NO_MASTER_MAPPING NO_GROUP_ASSIGNED].include?(status)
        []
      else
        ClaudeCellBuilder.build(required, comparison)
      end

      RowOutcome.new(
        source_sheet_name: row.sheet_name,
        source_row_number: row.source_row_number,
        generic_name: row.generic_name,
        generic_name_group: row.generic_name_group,
        generic_name_group_inferred: row.generic_name_group_inferred,
        hcpcs_code: row.hcpcs_code,
        status_flag: row.status_flag,
        master_tab: tab.name,
        matched_brand_column: match.brand.raw_header,
        match_confidence: match.confidence,
        match_method: match.method,
        source_column_used: row.source_column_used,
        required_count: required.size,
        actual_count: row.actual_insurances.size,
        validation_status: status,
        missing_insurances: comparison.missing,
        spelling_mismatches: spelling,
        extra_insurances: comparison.extras,
        claude_insurances: runs,
        notes: notes.join(" | "),
        insert_after_column: sheet.insert_after_column,
        header_row: sheet.header_row
      )
    end

    def validation_status_for(row, comparison)
      return "NO_DATA" if row.no_data
      return "FAIL_MISSING" if comparison.missing.any?
      return "REVIEW_SPELLING" if comparison.variants.any? { |variant| variant.kind == "typo" }

      "PASS"
    end

    def blank_mapping_outcome(row, sheet, match_method, validation_status, notes, tab_name = nil)
      RowOutcome.new(
        source_sheet_name: row.sheet_name,
        source_row_number: row.source_row_number,
        generic_name: row.generic_name,
        generic_name_group: row.generic_name_group,
        generic_name_group_inferred: row.generic_name_group_inferred,
        hcpcs_code: row.hcpcs_code,
        status_flag: row.status_flag,
        master_tab: tab_name,
        matched_brand_column: nil,
        match_confidence: 0.0,
        match_method: match_method,
        source_column_used: row.source_column_used,
        required_count: 0,
        actual_count: row.actual_insurances.size,
        validation_status: validation_status,
        missing_insurances: [],
        spelling_mismatches: [],
        extra_insurances: [],
        claude_insurances: [],
        notes: notes,
        insert_after_column: sheet.insert_after_column,
        header_row: sheet.header_row
      )
    end
  end
end
