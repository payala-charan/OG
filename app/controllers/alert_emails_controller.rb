class AlertEmailsController < ApplicationController
  def index
    @alert_emails = AlertEmail.all
  end

  def create
    @alert_email = AlertEmail.new(alert_email_params)
    if @alert_email.save
      redirect_to alert_emails_path, notice: 'Email saved successfully.'
    else
      redirect_to alert_emails_path, alert: 'Error saving email.'
    end
  end

  def destroy
    @alert_email = AlertEmail.find(params[:id])
    @alert_email.destroy
    redirect_to alert_emails_path, notice: 'Email removed.'
  end

  def validate_and_trigger
    last_validate = AutoValidateRecord.last
    last_ranking = AutoRankingRecord.last

    errors_found = false
    details = []

    validate_file_name = last_validate&.file.presence || "Unknown File"
    sheet_names = []

    if last_validate && last_validate.data
      last_validate.data.each do |key, value|
        if value.is_a?(Hash) && value.key?('match') && [false, 'false', "False", "false"].include?(value['match'].to_s.downcase)
          errors_found = true
          details << "- AutoValidate: Mismatch in '#{key}' (Expected: #{value['calc']}, Actual: #{value['actual']})"
        end
      end
    end

    if last_ranking && last_ranking.data
      sheets = last_ranking.data['sheets'] || []
      sheets.each do |sheet|
        sheet_names << sheet['sheet_name']
        rows = sheet['rows'] || []
        rows.each do |row|
          cells = row['cells'] || []
          cells.each do |cell|
            if ['failed', 'warn', 'error'].include?(cell['status'].to_s.downcase)
              errors_found = true
              details << "- AutoRanking: #{cell['status'].capitalize} in generic: #{row['generic_name']} (Expected: #{cell['expected']}, Actual: #{cell['actual']})"
            end
          end
        end
      end
    end

    if errors_found
      emails = AlertEmail.pluck(:email)
      
      summary_details = details.uniq.take(15).join("\n")
      summary_details += "\n... and #{details.uniq.size - 15} more errors." if details.uniq.size > 15
      
      render json: { 
        trigger_email: true, 
        emails: emails.join(','), 
        file_name: validate_file_name,
        sheet_names: sheet_names.uniq.join(', '),
        details: summary_details.presence || "No discrete mismatch values matched."
      }
    else
      render json: { trigger_email: false, message: "No validation or ranking errors found." }
    end
  end

  private

  def alert_email_params
    params.require(:alert_email).permit(:email)
  end
end
