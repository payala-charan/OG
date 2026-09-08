class TallyValidationsController < ApplicationController
  require "roo"

  before_action :require_login

  def index
    @records = current_user.tally_validation_records.order(created_at: :desc)
    @last_record = @records.first

    if @last_record
      data = @last_record.data
      # Parse JSON string if needed
      begin
        data = JSON.parse(data) if data.is_a?(String)
      rescue JSON::ParserError
        data = {}
      end

      # Ensure data is a hash
      data = {} unless data.is_a?(Hash)
      @validated_data = data["validated_rows"] || []
      @individual_file_name = @last_record.individual_file_name
      @grouped_file_name = @last_record.grouped_file_name
    else
      @validated_data = []
      @individual_file_name = nil
      @grouped_file_name = nil
    end
  end

  def upload
    if params[:individual_file].blank? || params[:grouped_file].blank?
      flash[:alert] = "Please upload both the Individual Records file and the Grouped Records file."
      redirect_to tally_validations_path and return
    end

    indiv_file = params[:individual_file]
    grp_file = params[:grouped_file]

    begin
      service = TallyValidationService.new(indiv_file.path, grp_file.path)
      result = service.call

      # Save results in DB
      TallyValidationRecord.where(user_id: current_user.id).destroy_all
      TallyValidationRecord.create!(
        data: {
          validated_rows: result[:validated_rows],
          individual_file_name: indiv_file.original_filename,
          grouped_file_name: grp_file.original_filename,
          validated_at: Time.current
        },
        user_id: current_user.id,
        user_email: current_user.email,
        individual_file_name: indiv_file.original_filename,
        grouped_file_name: grp_file.original_filename
      )

      flash[:notice] = "Spreadsheets tally validated successfully."
      redirect_to tally_validations_path
    rescue TallyValidationService::ValidationError => e
      flash[:alert] = e.message
      redirect_to tally_validations_path
    rescue => e
      flash[:alert] = "Error processing upload: #{e.message}"
      logger.error "Tally validation upload error: #{e.message}\n#{e.backtrace.join("\n")}"
      redirect_to tally_validations_path
    end
  end

  def clear_history
    TallyValidationRecord.where(user_id: current_user.id).destroy_all
    flash[:notice] = "Validation history cleared successfully."
    redirect_to tally_validations_path
  end
end
