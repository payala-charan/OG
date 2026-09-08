# frozen_string_literal: true

namespace :insurance_preference do
  desc "Shift a sample formula column and verify references (optional LibreOffice recalc)"
  task :verify_formulas, [:original, :annotated, :insert_col] => :environment do |_t, args|
    unless args[:original] && args[:annotated]
      puts "Usage: rake insurance_preference:verify_formulas[original.xlsx,annotated.xlsx,INSERT_COL]"
      next
    end

    insert_col = args[:insert_col].to_i
    insert_col = 2 if insert_col <= 0
    original = InsurancePreference::WorkbookAnnotator.new(args[:original], {}).collect_formula_snapshot(args[:original])
    annotated = InsurancePreference::WorkbookAnnotator.new(args[:annotated], {}).collect_formula_snapshot(args[:annotated])

    mismatches = []
    original.each do |addr, formula|
      sheet, cell = addr.split("!", 2)
      col_letters = cell[/[A-Z]+/]
      row = cell[/\d+/]
      col_idx = InsurancePreference::FormulaShifter.column_index(col_letters)
      new_col = col_idx >= insert_col ? col_idx + 1 : col_idx
      new_addr = "#{sheet}!#{InsurancePreference::FormulaShifter.column_letters(new_col)}#{row}"
      expected = InsurancePreference::FormulaShifter.shift_formula(formula, insert_col)
      actual = annotated[new_addr]
      mismatches << "#{addr} -> #{new_addr}: expected #{expected.inspect}, got #{actual.inspect}" unless actual == expected
    end

    if mismatches.empty?
      puts "Formula references match after column shift (#{original.size} formulas)."
    else
      puts "Formula mismatches:"
      mismatches.each { |line| puts "  #{line}" }
      abort
    end

    soffice = `which soffice`.strip
    if soffice.present?
      puts "LibreOffice found at #{soffice}. Recalc/value diff is left as an operator step:"
      puts "  soffice --headless --calc --convert-to csv #{args[:original]}"
      puts "  soffice --headless --calc --convert-to csv #{args[:annotated]}"
    else
      puts "LibreOffice (soffice) not found; skipped computed-value recalc. Formula-string check passed."
    end
  end
end
