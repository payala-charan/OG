# frozen_string_literal: true

module InsurancePreference
  class FormulaShifter
    CELL_REF = /(\$?)([A-Z]{1,3})(\$?)(\d{1,7})/

    COMPLEX_HINTS = [
      /[A-Za-z0-9_' ]+!/, # cross-sheet
      /\[.*\]/,           # external workbook
      /\{=/,              # array formula
      /#spill/i
    ].freeze

    def self.column_index(letters)
      letters.upcase.chars.reduce(0) { |n, ch| n * 26 + (ch.ord - 64) }
    end

    def self.column_letters(index)
      chars = +""
      n = index
      while n.positive?
        n, rem = (n - 1).divmod(26)
        chars.prepend((65 + rem).chr)
      end
      chars
    end

    # insert_col is the 1-based index of the newly inserted column.
    # Any reference at or after that column is bumped by one.
    def self.shift_formula(formula, insert_col)
      return formula if formula.nil?

      formula.to_s.gsub(CELL_REF) do
        abs_col = Regexp.last_match(1)
        letters = Regexp.last_match(2)
        abs_row = Regexp.last_match(3)
        row = Regexp.last_match(4)
        idx = column_index(letters)
        letters = column_letters(idx + 1) if idx >= insert_col
        "#{abs_col}#{letters}#{abs_row}#{row}"
      end
    end

    def self.complexity_warnings(formulas)
      warnings = []
      formulas.each do |addr, formula|
        COMPLEX_HINTS.each do |rx|
          if formula.to_s.match?(rx)
            warnings << "Complex formula at #{addr}: #{formula}"
            break
          end
        end
      end
      warnings
    end
  end
end
