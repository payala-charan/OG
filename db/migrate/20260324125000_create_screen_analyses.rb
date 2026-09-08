class CreateScreenAnalyses < ActiveRecord::Migration[7.0]
  def change
    create_table :screen_analyses do |t|
      t.string :title, null: false
      t.text :summary, null: false
      t.timestamps
    end
  end
end
