class TrigramFallbackService
  def initialize(schema_map = SchemaService.schema_map)
    @schema_map = schema_map
    @resolver = GenericResolver.new(schema_map)
  end

  # Try to fuzzy match `value` across all textual columns and return hits
  def fuzzy_search(value, limit_per_model: 20)
    @resolver.find_by_value(value, limit_per_model: limit_per_model)
  end
end
