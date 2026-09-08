# frozen_string_literal: true

module InsurancePreference
  class GroupInference
    def self.infer(generic_name)
      haystack = generic_name.to_s.downcase
      Config::GROUP_INFERENCE.each do |keyword, group|
        return group if haystack.include?(keyword)
      end
      nil
    end
  end
end
