class AutoValidationsController < ApplicationController
  before_action :require_login

  def index
  end

  def results
    @file_history = AutoValidateRecord
      .group(:file)
      .select('file, COUNT(*) AS row_count, MAX(created_at) AS latest_created_at')
      .order(Arel.sql('MAX(created_at) DESC'))

    if @file_history.empty?
      redirect_to auto_validation_path, alert: "No validation records found. Please run auto validation first."
      return
    end

    @selected_file = params[:file].presence
    if @selected_file
      @selected_file_summary = @file_history.to_a.find { |history| history.file == @selected_file }
      @selected_file ||= @file_history.first.file
      @selected_file_summary ||= @file_history.first
      @latest_record = AutoValidateRecord.where(file: @selected_file).order(created_at: :desc).first
      @validation_records = AutoValidateRecord.where(file: @selected_file).order(created_at: :asc).map(&:data).compact
    else
      @selected_file_summary = nil
      @latest_record = nil
      @validation_records = []
    end
  end
end