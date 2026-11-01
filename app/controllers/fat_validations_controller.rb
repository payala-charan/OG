# frozen_string_literal: true

class FatValidationsController < ApplicationController
  before_action :require_login
  before_action :set_run, only: [ :show, :screenshot ]

  def self.local_browser?(host)
    %w[localhost 127.0.0.1 ::1].include?(host.to_s.split(":").first)
  end

  def index
    @runs = current_user.fat_validation_runs.order(created_at: :desc).limit(25)
    @team_options = FatValidation::FatEnvironment.team_options
    @watched_run = current_user.fat_validation_runs.find_by(id: params[:run_id]) if params[:run_id].present?
  end

  def create
    environment = params[:environment].to_s
    team_id = params[:team_id].to_s
    report_type = params[:report_type].to_s
    data_source = params[:data_source].to_s

    unless FatValidation::FatEnvironment::ENVIRONMENTS.key?(environment)
      redirect_to fat_validations_path, alert: "Choose Local, Staging, or Production." and return
    end
    unless FatValidation::FatEnvironment::TEAMS.key?(team_id)
      redirect_to fat_validations_path, alert: "Choose a team." and return
    end
    unless report_type == "overview"
      redirect_to fat_validations_path, alert: "Only the Overview report is available right now." and return
    end
    unless data_source == "database"
      redirect_to fat_validations_path, alert: "Excel upload is not configured yet. Choose Database." and return
    end

    FatValidation::FatEnvironment.new(environment: environment, team_id: team_id).credentials

    run = current_user.fat_validation_runs.create!(
      environment: environment,
      team_id: team_id,
      report_type: report_type,
      data_source: data_source,
      status: :pending,
      progress_message: "Queued"
    )
    visible = self.class.local_browser?(request.host)
    enqueue_validation(run, visible: visible)
    notice = if visible
      "Validation is running in the FAT Chrome window on this computer. Opportunity values are colored there."
    else
      "Validation is running. The colored FAT Overview will show on this page when it finishes. It does not open a browser on your computer."
    end
    redirect_to fat_validations_path(run_id: run.id), notice: notice
  rescue FatValidation::ConfigurationError => e
    redirect_to fat_validations_path, alert: e.message
  end

  def show
    @results = @run.results.order(:generic_group, :id)
    respond_to do |format|
      format.html
      format.json { render json: @run.status_payload }
    end
  end

  def screenshot
    unless @run.highlight_screenshot.attached?
      head :not_found
      return
    end

    send_data @run.highlight_screenshot.download,
              type: "image/png",
              disposition: "inline",
              filename: @run.highlight_screenshot.filename.to_s
  end

  private

  def set_run
    @run = current_user.fat_validation_runs.find(params[:id])
  end

  def enqueue_validation(run, visible:)
    if Rails.env.development?
      Thread.new do
        Rails.application.executor.wrap do
          FatValidationJob.perform_now(run.id, visible: visible)
        end
      end
    else
      FatValidationJob.perform_later(run.id, visible: visible)
    end
  end
end
