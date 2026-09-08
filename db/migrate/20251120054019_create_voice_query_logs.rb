class CreateVoiceQueryLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :voice_query_logs do |t|
      t.text :query
      t.text :response
      t.string :result

      t.timestamps
    end
  end
end
