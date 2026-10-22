# frozen_string_literal: true

module DatabaseTransfer
  ColumnDefinition = Struct.new(:name, :data_type, :not_null, :default_sql, keyword_init: true)
end
