# frozen_string_literal: true

module InsurancePreference
  class TabResolver
    def initialize(tabs)
      @tabs = Array(tabs)
    end

    def resolve(group)
      return nil if Text.blank?(group)

      exact = @tabs.find { |tab| Text.exact_key(tab.name) == Text.exact_key(group) }
      return exact if exact

      group_key = Text.sorted_token_key(group)
      @tabs.find { |tab| Text.sorted_token_key(tab.name) == group_key }
    end
  end
end
