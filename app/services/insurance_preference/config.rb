# frozen_string_literal: true

module InsurancePreference
  module Config
    CLAUDE_COLUMN_NAME = ENV.fetch("CLAUDE_INSURANCES_COLUMN_NAME", "Claude Insurances")
    MATCH_ACCEPT_THRESHOLD = 0.65
    GENERIC_RETRY_THRESHOLD = 0.6
    TYPO_RATIO_THRESHOLD = 0.87

    SPECIAL_DISPLAY_OVERRIDES = {
      "GOVT EMP HOSPITAL ASSC." => { display: "GOVT EMP HOSPITAL ASSC", color: "red" },
      "INNOVAGE (PACE)" => { display: "INNOVAGE (PACE)", color: "red" }
    }.freeze

    # Most-specific-first keyword → generic_name_group.
    GROUP_INFERENCE = [
      ["efbemalenograstim", "PEGFILGRASTIM"],
      ["eflapegrastim", "PEGFILGRASTIM"],
      ["pegfilgrastim", "PEGFILGRASTIM"],
      ["tbo-filgrastim", "FILGRASTIM"],
      ["filgrastim", "FILGRASTIM"],
      ["bevacizumab", "BEVACIZUMAB"],
      ["trastuzumab", "TRASTUZUMAB"],
      ["infliximab", "INFLIXIMAB"],
      ["in-fliximab", "INFLIXIMAB"],
      ["rituximab", "RITUXIMAB"],
      ["tocilizumab", "TOCILIZUMAB"],
      ["actemra", "TOCILIZUMAB"],
      ["bendamustine", "BENDAMUSTINE"],
      ["leuprolide", "LEUPROLIDE ACETATE"],
      ["hyaluronate", "HYALURONATE SODIUM"]
    ].freeze

    # [group, generic_name matcher] => exact Master header text (or unique core).
    BRAND_MATCH_OVERRIDES = [
      {
        group: "INFLIXIMAB",
        generic_name: /infliximab\s*\(\s*in-?fliximab/i,
        master_header: "Generic Remicade"
      }
    ].freeze

    LEUPROLIDE_FAMILIES = %w[Camcevi Eligard Lupron].freeze

    LLM_PROVIDER = ENV.fetch("INSURANCE_PREF_LLM_PROVIDER", ENV.fetch("LLM_PROVIDER", "google"))
    LLM_MODEL = ENV.fetch("INSURANCE_PREF_LLM_MODEL", ENV.fetch("OPENAI_MODEL", "gpt-4o-mini"))
    LLM_DELAY_SECONDS = ENV.fetch("INSURANCE_PREF_LLM_DELAY", "0.25").to_f
  end
end
