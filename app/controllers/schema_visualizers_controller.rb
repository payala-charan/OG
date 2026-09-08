class SchemaVisualizersController < ApplicationController
  def index
    if params[:reset] == 'true'
      SchemaDatum.destroy_all
      redirect_to schema_visualizers_path, notice: "Ready to upload a new schema architecture."
      return
    end

    # Load existing schema if available
    @schema_data = SchemaDatum.first
    if @schema_data.present?
      begin
        parser = SchemaParserService.new(@schema_data.content)
        graph_data = parser.parse

        @nodes = graph_data[:tables].map do |t|
          {
            id: t[:name],
            label: t[:name].upcase,
            shape: 'box',
            margin: { top: 15, bottom: 15, left: 20, right: 20 },
            font: { size: 18, face: 'Inter, sans-serif', bold: true },
            color: { background: '#ffffff', border: '#4361ee', highlight: { background: '#4361ee', border: '#4361ee' } },
            borderWidth: 2,
            shadow: true,
            tableColumns: t[:columns]
          }
        end

        @edges = graph_data[:relationships].map do |rel|
          {
            from: rel[:from],
            to: rel[:to],
            arrows: 'to',
            color: rel[:inferred] ? { color: '#f72585', highlight: '#f72585' } : { color: '#a0aec0', highlight: '#4361ee' },
            dashes: rel[:inferred],
            width: 2,
            selectionWidth: 4
          }
        end
      rescue => e
        flash.now[:alert] = "Error parsing existing schema file: #{e.message}"
      end
    end
  end

  def create
    file = params[:schema_file]

    if file.blank?
      redirect_to schema_visualizers_path, alert: "Please upload a schema.rb file."
      return
    end

    begin
      schema_content = file.read
      
      # Clear previous and store only ONE schema file at a time
      SchemaDatum.destroy_all
      SchemaDatum.create!(content: schema_content)
      
      redirect_to schema_visualizers_path, notice: "Data mapped successfully!"
    rescue => e
      redirect_to schema_visualizers_path, alert: "Error saving schema file: #{e.message}"
    end
  end
end
