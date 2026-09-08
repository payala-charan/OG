# frozen_string_literal: true

module InsurancePreference
  class ClaudeCellBuilder
    Run = Struct.new(:text, :color, keyword_init: true)

    def self.build(required, comparison)
      return [] if required.nil? || required.empty?

      statuses = comparison.required_status
      ordered = required.sort_by { |name| Text.exact_key(name) }
      items = ordered.map { |req| item_for(req, statuses[req]) }

      extras = Array(comparison.extras).sort_by { |name| Text.exact_key(name) }
      extras.each do |extra|
        items << { text: extra, color: "yellow" }
      end

      runs_from(items)
    end

    def self.item_for(required, status)
      override = lookup_override(required)
      if override
        return { text: override[:display], color: override[:color] }
      end

      present = status&.present
      { text: required, color: present ? "black" : "red" }
    end

    def self.lookup_override(required)
      Config::SPECIAL_DISPLAY_OVERRIDES.each do |key, value|
        return value if Text.exact_key(key) == Text.exact_key(required)
      end
      nil
    end

    def self.runs_from(items)
      return [] if items.empty?

      runs = []
      items.each_with_index do |item, idx|
        prefix = idx.zero? ? "" : ", "
        if runs.last && runs.last.color == item[:color]
          runs.last.text = "#{runs.last.text}#{prefix}#{item[:text]}"
        else
          runs << Run.new(text: "#{prefix}#{item[:text]}", color: item[:color])
        end
      end
      runs
    end
  end
end
