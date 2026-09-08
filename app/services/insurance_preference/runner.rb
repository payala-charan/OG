# frozen_string_literal: true

require "fileutils"

module InsurancePreference
  class Runner
    def initialize(run)
      @run = run
    end

    def call
      claim = InsurancePreferenceValidationRun.where(id: @run.id, status: %w[pending failed]).update_all(
        status: InsurancePreferenceValidationRun.statuses[:parsing],
        error_message: nil,
        updated_at: Time.current
      )
      return if claim.zero? && !@run.parsing?

      @run.reload
      master_path = blob_to_tempfile(@run.master_file, "master")
      biosimilar_path = blob_to_tempfile(@run.biosimilar_file, "biosimilar")

      @run.update!(status: :validating, progress_message: "Comparing biosimilar rows to Master preferences")
      result = Validator.new(master_path: master_path.path, biosimilar_path: biosimilar_path.path).call

      persist_rows(result)
      @run.update!(
        warnings: result.warnings,
        progress_message: "Writing annotated workbook",
        summary: summarize(result)
      )

      output = annotate_workbook(biosimilar_path.path, result)
      attach_output(output)

      if @run.model_validation_enabled?
        @run.update!(status: :model_validating, progress_message: "Running optional model validation")
        run_model_validation
      end

      @run.update!(status: :complete, progress_message: "Complete", finished_at: Time.current)
    rescue StandardError => e
      @run.update!(status: :failed, error_message: e.message, progress_message: "Failed", finished_at: Time.current)
      raise
    ensure
      master_path&.close!
      biosimilar_path&.close!
    end

    private

    def persist_rows(result)
      now = Time.current
      records = result.rows.map do |outcome|
        {
          insurance_preference_validation_run_id: @run.id,
          source_sheet_name: outcome.source_sheet_name,
          source_row_number: outcome.source_row_number,
          generic_name: outcome.generic_name,
          generic_name_group: outcome.generic_name_group,
          generic_name_group_inferred: outcome.generic_name_group_inferred,
          hcpcs_code: outcome.hcpcs_code,
          status_flag: outcome.status_flag,
          master_tab: outcome.master_tab,
          matched_brand_column: outcome.matched_brand_column,
          match_confidence: outcome.match_confidence,
          match_method: outcome.match_method,
          source_column_used: outcome.source_column_used,
          required_count: outcome.required_count,
          actual_count: outcome.actual_count,
          validation_status: outcome.validation_status,
          missing_insurances: Array(outcome.missing_insurances).to_json,
          spelling_mismatches: Array(outcome.spelling_mismatches).to_json,
          extra_insurances: Array(outcome.extra_insurances).to_json,
          claude_insurances_json: outcome.claude_insurances.map { |run| { "text" => run.text, "color" => run.color } },
          notes: outcome.notes,
          created_at: now,
          updated_at: now
        }
      end
      InsurancePreferenceValidationRow.insert_all(records) if records.any?
    end

    def annotate_workbook(biosimilar_path, result)
      output_path = Rails.root.join("tmp", "insurance_pref_#{@run.id}_#{Time.current.to_i}.xlsx")
      FileUtils.mkdir_p(output_path.dirname)
      annotator = WorkbookAnnotator.new(
        biosimilar_path,
        {
          column_name: @run.claude_column_name.presence || Config::CLAUDE_COLUMN_NAME,
          sheets: result.sheet_annotations
        }
      )
      snapshot = annotator.collect_formula_snapshot(biosimilar_path) rescue {}
      warnings = Array(@run.warnings)
      warnings.concat(FormulaShifter.complexity_warnings(snapshot))
      @run.update!(warnings: warnings.uniq)
      annotator.call(output_path.to_s)
      output_path
    end

    def attach_output(path)
      filename = "biosimilar_claude_insurances_#{@run.id}.xlsx"
      @run.output_file.attach(
        io: File.open(path),
        filename: filename,
        content_type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      )
    end

    def run_model_validation
      rows = @run.validation_rows.where.not(validation_status: ModelValidator::SKIP_STATUSES)
      total = rows.count
      rows.find_each.with_index do |row, idx|
        @run.update_column(:progress_message, "Model validation #{idx + 1}/#{total}")
        attrs = ModelValidator.new(row).call
        row.create_model_validation_result!(attrs)
        sleep(Config::LLM_DELAY_SECONDS) if Config::LLM_DELAY_SECONDS.positive?
      end
    end

    def summarize(result)
      statuses = result.rows.group_by(&:validation_status).transform_values(&:count)
      tabs = result.rows.group_by(&:source_sheet_name).transform_values(&:count)
      { "status_counts" => statuses, "tab_counts" => tabs, "row_count" => result.rows.size }
    end

    def blob_to_tempfile(attachment, prefix)
      raise "Missing #{prefix} file" unless attachment.attached?

      ext = File.extname(attachment.filename.to_s)
      tmp = Tempfile.new([prefix, ext])
      tmp.binmode
      tmp.write(attachment.download)
      tmp.flush
      tmp
    end
  end
end
