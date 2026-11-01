# frozen_string_literal: true

module FatValidation
  # Whole-dollar values as shown on the Overview table, such as "$741,544".
  module Money
    module_function

    def parse_dollars(text)
      raw = text.to_s.strip
      return nil if raw.blank? || raw == "—" || raw == "-" || raw == "–"

      negative = raw.start_with?("-") || raw.include?("(")
      digits = raw.gsub(/[^\d.]/, "")
      return nil if digits.blank? || digits == "."

      whole = digits.split(".", 2).first.to_i
      negative ? -whole : whole
    end
  end
end
