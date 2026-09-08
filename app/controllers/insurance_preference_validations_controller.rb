# frozen_string_literal: true

class InsurancePreferenceValidationsController < ApplicationController
  before_action :require_login
  before_action :set_run, only: [:show, :results, :download, :destroy]

  def index
    @runs = current_user.insurance_preference_validation_runs.order(created_at: :desc)
  end

  def create
    if params[:master_file].blank? || params[:biosimilar_file].blank?
      flash[:alert] = "Please upload both the Master Preference Table and the Biosimilar sheet."
      redirect_to insurance_preference_validations_path and return
    end

    run = current_user.insurance_preference_validation_runs.create!(
      model_validation_enabled: ActiveModel::Type::Boolean.new.cast(params[:model_validation_enabled]) == true,
      claude_column_name: params[:claude_column_name].presence || InsurancePreference::Config::CLAUDE_COLUMN_NAME,
      master_file_name: params[:master_file].original_filename,
      biosimilar_file_name: params[:biosimilar_file].original_filename,
      progress_message: "Queued"
    )
    run.master_file.attach(params[:master_file])
    run.biosimilar_file.attach(params[:biosimilar_file])

    start_validation_job(run.id)

    redirect_to insurance_preference_validation_path(run)
  rescue StandardError => e
    flash[:alert] = "Could not start validation: #{e.message}"
    redirect_to insurance_preference_validations_path
  end

  def show
    load_rows
    respond_to do |format|
      format.html
      format.json { render json: @run.status_payload }
    end
  end

  def results
    load_rows
    render partial: "results", layout: false
  end

  def download
    unless @run.output_file.attached?
      flash[:alert] = "Annotated workbook is not ready yet."
      redirect_to insurance_preference_validation_path(@run) and return
    end

    send_data @run.output_file.download,
              filename: @run.output_file.filename.to_s,
              type: @run.output_file.content_type,
              disposition: "attachment"
  end

  def destroy
    @run.destroy
    flash[:notice] = "Validation run deleted."
    redirect_to insurance_preference_validations_path
  end

  private

  def set_run
    @run = current_user.insurance_preference_validation_runs.find(params[:id])
  end

  def load_rows
    @rows = @run.validation_rows.includes(:model_validation_result).order(:source_sheet_name, :source_row_number)
  end

  def start_validation_job(run_id)
    if solid_queue_ready?
      InsurancePreferenceValidationJob.perform_later(run_id)
      return if Rails.env.production?
    end

    # Local/dev has Solid Queue configured but no queue tables or worker.
    # Run in-process so an upload still completes.
    return if Rails.env.test?

    Thread.new do
      Rails.application.executor.wrap do
        InsurancePreferenceValidationJob.perform_now(run_id)
      end
    end
  end

  def solid_queue_ready?
    adapter = ActiveJob::Base.queue_adapter
    return false unless adapter.class.name.include?("SolidQueue")

    connection = if defined?(SolidQueue::Job)
      SolidQueue::Job.connection
    else
      ActiveRecord::Base.connection
    end
    connection.data_source_exists?("solid_queue_jobs")
  rescue StandardError
    false
  end
end

