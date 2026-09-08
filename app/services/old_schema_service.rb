class SchemaService
  # Adjust this list if model names differ
  SEARCHABLE_MODELS = [
    Payor, Insurance, Og, PayorPreference,
    User, Sample, PaymentFactor, Student,
    NameMatch, UploadedFile
  ]

  def self.schema_map
    @schema_map ||= SEARCHABLE_MODELS.each_with_object({}) do |m, h|
      # Use model.name.downcase as key (symbol)
      key = m.name.downcase.to_sym
      columns = m.columns_hash.transform_values do |c|
        { type: c.type, name: c.name, sql_type: c.sql_type }
      end
      h[key] = { model: m, columns: columns }
    end
  end

  def self.models_with_column(column_name)
    schema_map.select { |_k, info| info[:columns].key?(column_name.to_s) }.map { |_k, i| i[:model] }
  end
end
