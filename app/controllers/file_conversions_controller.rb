class FileConversionsController < ApplicationController
  def index
  end

  def convert
    uploaded_file = params[:file]
    if uploaded_file.nil?
      redirect_to file_conversions_path, alert: "Please upload a file first."
      return
    end

    original_filename = uploaded_file.original_filename
    input_path = uploaded_file.tempfile.path
    
    # Define output path
    timestamp = Time.now.strftime("%Y%m%d%H%M%S")
    base_name = File.basename(original_filename, ".*")
    output_filename = "#{base_name}_converted_#{timestamp}.xlsx"
    output_path = Rails.root.join('tmp', output_filename).to_s

    begin
      converter = FileToXlsxConverter.new(
        input_path: input_path,
        output_path: output_path,
        original_filename: original_filename
      )
      converter.call

      send_file output_path, filename: output_filename, type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", disposition: "attachment"
    rescue => e
      Rails.logger.error("Conversion failed: #{e.message}")
      redirect_to file_conversions_path, alert: "Conversion failed: #{e.message}"
    end
  end
end
