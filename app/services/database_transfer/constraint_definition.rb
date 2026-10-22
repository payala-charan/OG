# frozen_string_literal: true

module DatabaseTransfer
  ConstraintDefinition = Struct.new(:name, :kind, :definition, :target_schema, :target_table, keyword_init: true) do
    def index_backed?
      %w[p u x].include?(kind)
    end
  end
end
