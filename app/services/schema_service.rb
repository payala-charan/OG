# app/services/schema_service.rb
# Builds an in-memory schema_map for the searchable models.
# Key: model_name.downcase.to_sym
# Value: { model: ModelClass, columns: { column_name => { type:, name:, sql_type: } } }
class SchemaService
  # Adjust this list if model names differ; keep model constants here.
  SEARCHABLE_MODELS = [
    Payor, Insurance, Og, PayorPreference,
    User, Sample, PaymentFactor, Student,
    NameMatch, UploadedFile
  ].freeze

  def self.schema_map
    @schema_map ||= build_schema_map
  end

  def self.models_with_column(column_name)
    column_name = column_name.to_s
    schema_map.select { |_k, info| info[:columns].key?(column_name) }.map { |_k, info| info[:model] }
  end

  def self.build_schema_map
    SEARCHABLE_MODELS.each_with_object({}) do |m, h|
      key = m.name.downcase.to_sym
      columns = m.columns_hash.transform_values do |c|
        { type: c.type, name: c.name, sql_type: c.sql_type }
      end
      h[key] = { model: m, columns: columns }
    end
  end

  # convenience to return a flat hash of table_name => [cols]
  def self.simple_map
    schema_map.each_with_object({}) do |(k, info), memo|
      memo[k.to_s] = info[:columns].keys
    end
  end
end
