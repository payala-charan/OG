# frozen_string_literal: true

class GmailExtractionsController < ApplicationController
  def index
    @gmail_connection = current_user.gmail_connection
    @extractions = current_user.gmail_extractions.recent
    @gmail_extraction = GmailExtraction.new
  end

  def show
    @extraction = current_user.gmail_extractions.find(params[:id])
    @emails = @extraction.gmail_extracted_emails.order(sent_at: :desc, id: :desc)
    @emails = @emails.page(params[:page]).per(50)
  end

  def create
    if current_user.gmail_connection.nil?
      redirect_to gmail_extractions_path, alert: "Connect your Google account first."
      return
    end

    @gmail_extraction = current_user.gmail_extractions.build(
      extraction_params.merge(gmail_connection: current_user.gmail_connection)
    )
    if @gmail_extraction.save
      GmailExtractionJob.perform_async(@gmail_extraction.id)
      redirect_to @gmail_extraction, notice: "Import started. Large mailboxes (e.g. one year) can take a while. Refresh to see status and results."
    else
      @gmail_connection = current_user.gmail_connection
      @extractions = current_user.gmail_extractions.recent
      render :index, status: :unprocessable_content
    end
  end

  private

  def extraction_params
    params.require(:gmail_extraction).permit(:recipient_email, :start_on, :end_on)
  end
end
