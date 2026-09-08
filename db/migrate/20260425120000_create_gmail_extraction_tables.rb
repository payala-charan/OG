# frozen_string_literal: true

class CreateGmailExtractionTables < ActiveRecord::Migration[8.0]
  def change
    create_table :gmail_connections do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :access_token
      t.text :refresh_token
      t.string :google_email, null: false, default: ""
      t.datetime :token_expires_at
      t.timestamps
    end

    create_table :gmail_extractions do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.references :gmail_connection, null: false, foreign_key: true, index: true
      t.string :recipient_email, null: false
      t.date :start_on, null: false
      t.date :end_on, null: false
      t.string :status, null: false, default: "pending"
      t.text :error_message
      t.integer :total_fetched, default: 0, null: false
      t.timestamps
    end

    create_table :gmail_extracted_emails do |t|
      t.references :gmail_extraction, null: false, foreign_key: true, index: true
      t.string :gmail_message_id, null: false
      t.string :subject, default: "", null: false
      t.text :body_text
      t.datetime :sent_at
      t.timestamps
    end

    add_index :gmail_extracted_emails, [ :gmail_extraction_id, :gmail_message_id ],
      unique: true, name: "index_gmail_extracted_emails_on_extraction_and_gmail_id"
  end
end
