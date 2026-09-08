require "set"

class SchemaParserService
  def initialize(schema_text)
    @schema_text = schema_text
    @tables = []
    @relationships = []
  end

  def parse
    current_table = nil

    @schema_text.each_line do |line|
      line = line.strip

      # 1. Match create_table
      if line.match(/^create_table\s+"([^"]+)"/) || line.match(/^create_table\s+:'([^']+)'/) || line.match(/^create_table\s+:([^,\s]+)/)
        table_name = $1
        current_table = { name: table_name, columns: [{ name: "id", type: "primary_key" }] }
        @tables << current_table
      
      # 2. Match column definitions inside a table
      elsif current_table && line.match(/^t\.([a-zA-Z0-9_]+)\s+"([^"]+)"/)
        type = $1
        col_name = $2
        
        unless %w[index foreign_key].include?(type)
          current_table[:columns] << { name: col_name, type: type }
        end

      # 3. Match end of table block
      elsif current_table && line == "end"
        current_table = nil
      
      # 4. Match explicit foreign keys
      elsif line.match(/^add_foreign_key\s+"([^"]+)",\s+"([^"]+)"/)
        from_table = $1
        to_table = $2
        @relationships << { from: from_table, to: to_table, inferred: false }
      end
    end

    infer_relationships

    {
      tables: @tables,
      relationships: @relationships.uniq { |r| [r[:from], r[:to]] }
    }
  end

  private

  def infer_relationships
    table_names = @tables.map { |t| t[:name] }.to_set

    @tables.each do |table|
      table[:columns].each do |col|
        if col[:name].end_with?("_id")
          possible_singular_target = col[:name].delete_suffix("_id")
          
          # Very basic pluralization rule for inference
          possible_plural_target = possible_singular_target + "s"
          possible_plural_target2 = possible_singular_target.end_with?("y") ? possible_singular_target.delete_suffix("y") + "ies" : nil

          target = if table_names.include?(possible_plural_target)
                     possible_plural_target
                   elsif possible_plural_target2 && table_names.include?(possible_plural_target2)
                     possible_plural_target2
                   else
                     nil
                   end

          if target && target != table[:name]
            # Add unless an explicit foreign key already exists
            exists = @relationships.any? { |r| r[:from] == table[:name] && r[:to] == target }
            unless exists
              @relationships << { from: table[:name], to: target, inferred: true }
            end
          end
        end
      end
    end
  end
end
