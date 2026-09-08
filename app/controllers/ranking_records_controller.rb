class RankingRecordsController < ApplicationController
  require "json"

  def index
    @record = RankingRecord.where(user_id: current_user&.id).order(created_at: :desc).first
  end

  def new
  end

  def create
    file = params[:file]
    team_id = params[:team_id].presence || "198"
    period_id = params[:accounting_period_id].presence || "7"

    if file.blank?
      redirect_to new_ranking_record_path, alert: "Please upload a file"
      return
    end

    processor_result = RankingProcessor.new(
      file: file,
      team_id: team_id,
      period_id: period_id,
      user: current_user
    ).call

    if processor_result[:success]
      redirect_to ranking_record_path(processor_result[:record])
    else
      redirect_to new_ranking_record_path, alert: processor_result[:error]
    end
  end

  def show
    @record = RankingRecord.find(params[:id])
    @sheet_sections = @record.sheet_sections
    @debug_mismatches = Array(@record.data&.dig("debug_mismatches"))
    @debug_cells = Array(@record.data&.dig("debug_cells"))
  end

  def lookup_insurances
    # debugger
    group = params[:generic_name_group].to_s.upcase.strip
    payor = normalize(params[:payor])
    period = params[:accounting_period_id].presence || 7

    records = PayorPreference.where(
      generic_name_group: group,
      accounting_period_id: period,
      payor: payor
    )

    raw = records.pluck(:insurances).compact.uniq
    parsed = raw.flat_map { |v| parse_insurance_names(v) }.uniq

    render json: {
      generic_name_group: group,
      payor: payor,
      accounting_period_id: period.to_i,
      found_records: records.size,
      raw_insurances: raw,
      parsed_insurances: parsed
    }
  end

  private

  def normalize(str)
    str.to_s.downcase.strip
  end

  def parse_insurance_names(raw)
    inner = parse_insurance_raw_inner(raw)
    inner.map { |n| normalize(n) }.reject(&:blank?).uniq
  end

  def parse_insurance_raw_inner(raw)
    case raw
    when nil
      []
    when Array
      raw.flat_map { |x| parse_insurance_raw_inner(x) }
    when String
      s = raw.strip
      return [] if s.blank?

      begin
        parsed = JSON.parse(s)
        parse_insurance_raw_inner(parsed)
      rescue JSON::ParserError, TypeError
        parse_insurance_non_json_string(s)
      end
    else
      parse_insurance_raw_inner(raw.to_s)
    end
  end

  def parse_insurance_non_json_string(s)
    obj = Psych.safe_load(
      s,
      permitted_classes: [Array, String],
      permitted_symbols: [],
      aliases: true
    )
    case obj
    when Array
      obj.flat_map { |x| parse_insurance_raw_inner(x) }
    when String
      return [obj] if obj.strip == s.strip
      parse_insurance_raw_inner(obj)
    else
      comma_split_insurance_names(s)
    end
  rescue Psych::Exception, TypeError, ArgumentError
    comma_split_insurance_names(s)
  end

  def comma_split_insurance_names(s)
    cleaned = s.delete_prefix("[").delete_suffix("]").tr('"', "").tr("'", "")
    cleaned.split(/[,|]/).map(&:strip).reject(&:blank?)
  end
end
