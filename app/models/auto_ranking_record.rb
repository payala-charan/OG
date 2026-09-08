class AutoRankingRecord < ApplicationRecord
  # Normalizes stored JSON into an array of { "sheet_name", "headers", "rows" }.
  def sheet_sections
    d = data
    return [] if d.blank?

    h = d.is_a?(Hash) ? d.with_indifferent_access : {}.with_indifferent_access

    if h[:sheets].present?
      h[:sheets].map do |s|
        sh = s.is_a?(Hash) ? s.stringify_keys : {}
        {
          "sheet_name" => sh["sheet_name"].presence || "Sheet",
          "headers" => Array(sh["headers"]),
          "rows" => Array(sh["rows"])
        }
      end
    elsif h[:rows].present? || h[:headers].present?
      [
        {
          "sheet_name" => "Results",
          "headers" => Array(h[:headers]),
          "rows" => Array(h[:rows])
        }
      ]
    else
      []
    end
  end

  def total_ranking_row_count
    sheet_sections.sum { |s| Array(s["rows"]).size }
  end

  def max_ranking_payor_columns
    sheet_sections.map { |s| Array(s["headers"]).size }.max.to_i
  end
end