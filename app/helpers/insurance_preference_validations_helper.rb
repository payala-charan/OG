# frozen_string_literal: true

module InsurancePreferenceValidationsHelper
  def ip_status_chip(status)
    kind = case status.to_s
    when "PASS" then "pass"
    when "REVIEW_SPELLING", "REVIEW" then "review"
    when "FAIL_MISSING", "FAIL" then "fail"
    else "neutral"
    end
    content_tag(:span, status.to_s.presence || "—", class: "ip-chip ip-chip-#{kind}")
  end

  def ip_agree_chip(result)
    return content_tag(:span, "—", class: "ip-chip ip-chip-neutral") unless result

    if result.agrees_with_code
      content_tag(:span, "Agrees", class: "ip-chip ip-chip-pass")
    else
      content_tag(:span, "Disagrees", class: "ip-chip ip-chip-fail")
    end
  end

  def ip_list_preview(values)
    Array(values).first(8).join(", ").presence || "—"
  end
end
