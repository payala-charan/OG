# frozen_string_literal: true

module InsurancePreference
  class InsuranceComparator
    Result = Struct.new(
      :missing,
      :variants,
      :extras,
      :present,
      :required_status,
      keyword_init: true
    )

    Present = Struct.new(:required, :actual, :kind, :similarity, keyword_init: true)
    RequiredStatus = Struct.new(:required, :present, :actual, :kind, :similarity, keyword_init: true)

    def initialize(required, actual)
      @required = Array(required).map { |name| Text.collapse_ws(name) }.reject(&:empty?).uniq
      @actual = Array(actual).map { |name| Text.collapse_ws(name) }.reject(&:empty?)
    end

    def call
      consumed = Array.new(@actual.length, false)
      statuses = {}
      variants = []
      present = []

      @required.each do |req|
        match = match_rules_1_to_3(req, consumed)
        next unless match

        apply_present!(statuses, present, variants, req, match)
      end

      apply_sheet_side_merges!(statuses, present, variants, consumed)
      apply_master_side_merges!(statuses, present, variants, consumed)

      missing = @required.reject { |req| statuses[req]&.present }
      missing.each do |req|
        statuses[req] = RequiredStatus.new(required: req, present: false, actual: nil, kind: "missing", similarity: 0.0)
      end

      extras = []
      @actual.each_with_index do |act, idx|
        next if consumed[idx]
        next if fuzzy_against_required?(act)

        extras << act
      end

      Result.new(
        missing: missing,
        variants: variants,
        extras: extras,
        present: present,
        required_status: statuses
      )
    end

    private

    def apply_present!(statuses, present, variants, req, match)
      statuses[req] = RequiredStatus.new(
        required: req,
        present: true,
        actual: match[:actual],
        kind: match[:kind],
        similarity: match[:similarity]
      )
      record = Present.new(required: req, actual: match[:actual], kind: match[:kind], similarity: match[:similarity])
      present << record
      variants << record unless match[:kind] == "exact"
    end

    def match_rules_1_to_3(req, consumed)
      exact = find_actual(consumed, prefer_unconsumed: true) { |act| Text.exact_key(act) == Text.exact_key(req) }
      return consume(exact, kind: "exact", similarity: 1.0, consumed: consumed) if exact

      typo = find_actual(consumed, prefer_unconsumed: true) do |act|
        SequenceMatcher.new(Text.collapse_ws(req), Text.collapse_ws(act)).ratio >= Config::TYPO_RATIO_THRESHOLD
      end
      if typo
        ratio = SequenceMatcher.new(Text.collapse_ws(req), Text.collapse_ws(@actual[typo])).ratio
        return consume(typo, kind: "typo", similarity: ratio, consumed: consumed)
      end

      paren = find_actual(consumed, prefer_unconsumed: true) do |act|
        parenthetical_variant?(req, act)
      end
      return consume(paren, kind: "parenthetical", similarity: 1.0, consumed: consumed) if paren

      nil
    end

    def parenthetical_variant?(req, act)
      Text.exact_key(Text.strip_trailing_paren(req)) == Text.exact_key(act) ||
        Text.exact_key(req) == Text.exact_key(Text.strip_trailing_paren(act))
    end

    def apply_sheet_side_merges!(statuses, present, variants, consumed)
      unmatched = @required.reject { |req| statuses[req]&.present }
      return if unmatched.size < 2

      @actual.each_with_index do |act, idx|
        next if consumed[idx]

        pair = find_concat_pair(unmatched, act)
        next unless pair

        pair.each do |req|
          apply_present!(
            statuses,
            present,
            variants,
            req,
            { actual: act, kind: "delimiter_merge_sheet", similarity: 1.0 }
          )
        end
        consumed[idx] = true
        unmatched -= pair
      end
    end

    def apply_master_side_merges!(statuses, present, variants, consumed)
      unmatched_required = @required.reject { |req| statuses[req]&.present }
      unmatched_actual_idxs = @actual.each_index.reject { |idx| consumed[idx] }

      unmatched_required.each do |req|
        pair = find_actual_concat_pair(req, unmatched_actual_idxs)
        next unless pair

        pair.each { |idx| consumed[idx] = true }
        unmatched_actual_idxs -= pair
        apply_present!(
          statuses,
          present,
          variants,
          req,
          {
            actual: "#{@actual[pair[0]]} #{@actual[pair[1]]}",
            kind: "delimiter_merge_master",
            similarity: 1.0
          }
        )
      end
    end

    def find_concat_pair(required_names, actual)
      actual_key = Text.exact_key(actual)
      required_names.combination(2).each do |left, right|
        return [left, right] if Text.exact_key("#{left} #{right}") == actual_key
        return [left, right] if Text.exact_key("#{right} #{left}") == actual_key
      end
      nil
    end

    def find_actual_concat_pair(required_name, actual_idxs)
      req_key = Text.exact_key(required_name)
      actual_idxs.combination(2).each do |i, j|
        return [i, j] if Text.exact_key("#{@actual[i]} #{@actual[j]}") == req_key
        return [i, j] if Text.exact_key("#{@actual[j]} #{@actual[i]}") == req_key
      end
      nil
    end

    def fuzzy_against_required?(actual)
      @required.any? do |req|
        SequenceMatcher.new(Text.collapse_ws(req), Text.collapse_ws(actual)).ratio >= Config::TYPO_RATIO_THRESHOLD
      end
    end

    def find_actual(consumed, prefer_unconsumed:)
      order = if prefer_unconsumed
        (0...@actual.length).sort_by { |idx| consumed[idx] ? 1 : 0 }
      else
        (0...@actual.length).to_a
      end

      order.each do |idx|
        return idx if yield(@actual[idx])
      end
      nil
    end

    def consume(idx, kind:, similarity:, consumed:)
      consumed[idx] = true
      { actual: @actual[idx], kind: kind, similarity: similarity }
    end
  end
end
