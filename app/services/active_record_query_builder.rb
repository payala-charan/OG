# class ActiveRecordQueryBuilder
#   def initialize(schema_map = SchemaService.schema_map)
#     @schema_map = schema_map
#   end

#   # filters: [{ "column" => "...", "op" => "=", "value" => ... }]
#   # select_cols: optional array
#   def build_and_run(table_sym, filters = [], select_cols: nil, limit: 200)
#     info = @schema_map[table_sym.to_sym] or raise "Unknown table #{table_sym}"
#     model = info[:model]
#     query = model.all

#     Array(filters).each do |f|
#       col = f["column"].to_s
#       op = f["op"] || "="
#       val = f["value"]

#       raise "Unknown column #{col} for #{table_sym}" unless info[:columns].key?(col)

#       col_type = info[:columns][col][:type]
#       # Numeric columns
#       if [:integer, :float, :decimal].include?(col_type) || (col_type == :decimal)
#         # try to coerce numeric
#         numeric_val = begin
#           Float(val)
#         rescue
#           nil
#         end
#         if numeric_val.nil?
#           raise "Value #{val.inspect} is not numeric for column #{col}"
#         end
#         query = query.where("#{col} #{op} ?", numeric_val)
#       elsif col_type == :boolean
#         bool_val = ActiveRecord::Type::Boolean.new.cast(val)
#         query = query.where(col => bool_val)
#       else
#         # textual columns: use exact (op== '=') or ILIKE for partial
#         if op == "="
#           query = query.where(col => val)
#         else
#           query = query.where("#{col} ILIKE ?", "%#{sanitize_sql_like(val.to_s)}%")
#         end
#       end
#     end

#     query = query.select(select_cols) if select_cols.present?
#     query.limit(limit)
#   end

#   private

#   def sanitize_sql_like(string)
#     ActiveRecord::Base.sanitize_sql_like(string.to_s)
#   end
# end



# app/services/active_record_query_builder.rb
class ActiveRecordQueryBuilder
  NAME_LIKE_CANDIDATES = %w[name title code generic_name short_name].freeze

  def initialize(schema_map = SchemaService.schema_map)
    @schema_map = schema_map
  end

  # filters: [{ table: "insurance", column: "payor_id", op: "=", value: "anthem" }]
  def build_and_run(table_sym, filters = [], select_cols: nil, limit: 200)
    _info = @schema_map[table_sym.to_sym] or raise "Unknown table #{table_sym}"
    base_model = _info[:model]
    base_table = base_model.table_name
    query = base_model.all
    joined_tables = Set.new

    Array(filters).each do |f|
      table_name = (f["table"] || table_sym).to_s.downcase
      # raw_table = (f["table"] || table_sym).to_s
      # table_name = @schema_map[raw_table.to_sym][:model].table_name   # always plural + exact
      col        = f["column"].to_s
      op         = (f["op"] || "=").to_s.downcase
      val        = f["value"]

      raise "Unknown table #{table_name}" unless @schema_map.key?(table_name.to_sym)

      table_info = @schema_map[table_name.to_sym]
      model      = table_info[:model]
      columns    = table_info[:columns]

      raise "Unknown column #{col} for #{table_name}" unless columns.key?(col)

      # auto join if filter references another table
      if table_name != table_sym.to_s
        query = auto_join(query, base_model, model, joined_tables)
      end

      # FK smart resolution (e.g. payor_id => "anthem")
      if fk_string_value_needs_resolution?(columns[col][:type], col, val)
        resolved = try_resolve_foreign_key_to_associated_filter(
          query: query,
          base_model: base_model,
          filter_table: table_name,
          col: col,
          op: op,
          val: val,
          joined_tables: joined_tables
        )

        if resolved.is_a?(ActiveRecord::Relation)
          query = resolved
          next
        end
      end

      # normal filtering
      col_type = columns[col][:type]
      query = apply_filter(query, table_name, col, col_type, op, val)
    end

    if select_cols.present?
      query = query.select(*normalize_select_columns(select_cols, base_model))
    end

    query.limit(limit)
  end

  #######################################################
  # Foreign key resolution
  #######################################################
  def fk_string_value_needs_resolution?(col_type, col_name, val)
    col_name.to_s.end_with?("_id") && !numeric_string?(val)
  end

  def numeric_string?(v)
    return true if v.is_a?(Integer) || v.is_a?(Float)
    Float(v)
    true
  rescue
    false
  end

  def try_resolve_foreign_key_to_associated_filter(query:, base_model:, filter_table:, col:, op:, val:, joined_tables:)
    fk = col.to_s

    owning_info  = @schema_map[filter_table.to_sym]
    owning_model = owning_info[:model]
    owning_table = owning_model.table_name

    # Step 1: FK association detection
    assoc = owning_model.reflect_on_all_associations.find { |a| a.foreign_key.to_s == fk }

    if assoc
      related_model = assoc.klass

      # Join base -> owning
      if owning_table != base_model.table_name
        query = auto_join(query, base_model, owning_model, joined_tables)
      end

      # Join owning -> related
      if related_model.table_name != owning_table
        query = auto_join(query, owning_model, related_model, joined_tables, base_model_override: owning_model)
      end

      name_col = find_name_like_column_for_model(related_model)
      if name_col
        return query.where("#{related_model.table_name}.#{name_col} ILIKE ?", "%#{sanitize_sql_like(val)}%")
      end
    end

    # Step 2: infer table name (payor_id → payor)
    inferred_table = fk.sub(/_id$/, '')

    if @schema_map.key?(inferred_table.to_sym)
      related_info  = @schema_map[inferred_table.to_sym]
      related_model = related_info[:model]

      # Join base -> owning
      if owning_table != base_model.table_name
        query = auto_join(query, base_model, owning_model, joined_tables)
      end

      assoc2 = owning_model.reflect_on_all_associations.find { |a| a.klass == related_model }
      if assoc2
        query = auto_join(query, owning_model, related_model, joined_tables, base_model_override: owning_model)
      end

      name_col = find_name_like_column_for_model(related_model)
      if name_col
        return query.where("#{related_model.table_name}.#{name_col} ILIKE ?", "%#{sanitize_sql_like(val)}%")
      end
    end

    nil
  end

  #######################################################
  # JOIN logic — corrected signature
  #######################################################
  def auto_join(query, base_model, target_model, joined_tables, base_model_override: nil)
    relation = query
    base     = base_model_override || base_model

    assoc = find_association(base, target_model)
    raise "No relation between #{base} and #{target_model}" unless assoc

    tname = target_model.table_name.to_sym
    return relation if joined_tables.include?(tname)

    joined_tables << tname
    relation.joins(assoc.name)
  end

  def find_association(base_model, target_model)
    base_model.reflect_on_all_associations.find { |a| a.klass == target_model }
  end

  #######################################################
  # Apply filters
  #######################################################
  def apply_filter(query, table_name, col, col_type, op, val)
    #full_col = "#{table_name}.#{col}"
    model = @schema_map[table_name.to_sym][:model]
    real_table = model.table_name   # always gives correct plural
    full_col = "#{real_table}.#{col}"

    case col_type
    when :integer, :float, :decimal
      numeric = cast_to_number(val, full_col)
      query.where("#{full_col} #{sql_op(op)} ?", numeric)

    when :boolean
      bool = ActiveRecord::Type::Boolean.new.cast(val)
      query.where(full_col => bool)

    when :date, :datetime
      parsed = cast_to_date(val, full_col)
      query.where("#{full_col} #{sql_op(op)} ?", parsed)

    else
      apply_text_filter(query, full_col, op, val)
    end
  end

  def apply_text_filter(query, full_col, op, val)
    case op
    when "=", "eq"
      query.where(full_col => val)
    when "like", "contains"
      query.where("#{full_col} ILIKE ?", "%#{sanitize_sql_like(val)}%")
    when "starts_with"
      query.where("#{full_col} ILIKE ?", "#{sanitize_sql_like(val)}%")
    when "ends_with"
      query.where("#{full_col} ILIKE ?", "%#{sanitize_sql_like(val)}")
    else
      raise "Unknown string operator #{op}"
    end
  end

  #######################################################
  # Helpers
  #######################################################
  def cast_to_number(val, col)
    Float(val)
  rescue
    raise "Value #{val.inspect} is not numeric for #{col}"
  end

  def cast_to_date(val, col)
    Date.parse(val.to_s)
  rescue
    raise "Value #{val.inspect} is not a valid date for #{col}"
  end

  def sql_op(op)
    {
      "="  => "=",
      "eq" => "=",
      ">"  => ">",
      "<"  => "<",
      ">=" => ">=",
      "<=" => "<=",
      "!=" => "!=",
      "<>" => "!="
    }[op] || raise("Invalid operator #{op}")
  end

  def normalize_select_columns(cols, base_model)
    table = base_model.table_name 
    cols.map do |c|
      c.include?(".") ? c : "#{base_model.table_name}.#{c}"
    end
  end

  def sanitize_sql_like(str)
    ActiveRecord::Base.sanitize_sql_like(str.to_s)
  end

  def find_name_like_column_for_model(model)
    _info = @schema_map[model.name.downcase.to_sym]
    return nil unless _info
    NAME_LIKE_CANDIDATES.find { |c| _info[:columns].key?(c) }
  end
end
