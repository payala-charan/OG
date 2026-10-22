# frozen_string_literal: true

module DatabaseTransfer
  # A table pulled in by the dependency walk, with the foreign keys that explain it.
  TableDependency = Struct.new(:name, :reasons, :chain, :direction, keyword_init: true) do
    def chain_label
      chain.join(direction == :referencing ? " ← " : " → ")
    end
  end
end
