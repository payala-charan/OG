module ProductPreferenceRecordsHelper

  def formula_for(header)
    key = header.to_s.strip.upcase

    formulas = {
      "CMS REIMBURSEMENT PER PACKAGE" =>
        "Formula: (REIMBURSEMENT PER BILLING UNIT × BILLING UNIT PER PACKAGE SIZE)\nExample: 31.99 × 100 = 3199",

      "COST PER UNIT 340B" =>
        "Formula: (COST 340B ÷ BILLING UNIT PER PACKAGE SIZE)\nExample: 741 ÷ 100 = 7.41",

      "CMS MARGIN 340B COST" =>
        "Formula: (CMS REIMBURSEMENT PER PACKAGE - COST 340B)\nExample: 3199 - 741 = 2458",

      "CMS PERCENT MARGIN" =>
        "Formula: (CMS MARGIN 340B COST ÷ COST 340B) × 100\nExample: (2458 ÷ 741) × 100",

      "CMS MARGIN GPO COST" =>
        "Formula: (CMS REIMBURSEMENT PER PACKAGE - GPO COST)",

      "GPO PERCENT MARGIN" =>
        "Formula: (CMS MARGIN GPO COST ÷ GPO COST) × 100",

      "BLENDED CMS PERCENT MARGIN" =>
        "Formula: (BLENDED CMS MARGIN 340B COST ÷ BLENDED COST 340B) × 100",

      "BLENDED GPO PERCENT MARGIN" =>
        "Formula: (BLENDED CMS MARGIN GPO COST ÷ BLENDED GPO COST) × 100"
    }

    formulas[key] || "No formula available"
  end

end