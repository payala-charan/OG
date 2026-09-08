class GenericResolver
  def initialize(schema_map = SchemaService.schema_map)
    @schema_map = schema_map
  end

  # Free-text value search across string/text columns using ILIKE (trigram backed)
  # returns a hash: { table_sym => ActiveRecord::Relation }
  def find_by_value(value, limit_per_model: 20)
    results = {}
    @schema_map.each do |table_key, info|
      model = info[:model]
      string_columns = info[:columns].select { |_name, col| [:string, :text].include?(col[:type]) }.keys
      next if string_columns.empty?

      conds = string_columns.map { |c| "#{model.table_name}.#{c} ILIKE :q" }.join(" OR ")
      rows = model.where(conds, q: "%#{sanitize_sql_like(value)}%").limit(limit_per_model)
      results[table_key] = rows if rows.exists?
    end
    results
  end

  # Trigram similarity search on a preferred column
  def trigram_search(model, column, q, limit: 20, min_similarity: 0.25)
    # Use similarity() if pg_trgm installed; order by similarity desc
    model.where("similarity(#{column}, ?) > ?", q, min_similarity)
         .order(Arel.sql("similarity(#{column}, #{ActiveRecord::Base.connection.quote(q)}) DESC"))
         .limit(limit)
  end

  private

  # Rails sanitize for LIKE pattern
  def sanitize_sql_like(string)
    ActiveRecord::Base.sanitize_sql_like(string.to_s)
  end
end
