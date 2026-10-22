# frozen_string_literal: true

module DatabaseTransfer
  SequenceDefinition = Struct.new(
    :name, :column_name, :data_type, :start_value, :increment_by,
    :min_value, :max_value, :cache_size, :cycle,
    keyword_init: true
  )
end
