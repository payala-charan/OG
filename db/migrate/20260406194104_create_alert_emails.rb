class CreateAlertEmails < ActiveRecord::Migration[8.0]
  def change
    create_table :alert_emails do |t|
      t.string :email

      t.timestamps
    end
  end
end
