class CreateStudents < ActiveRecord::Migration[8.0]
  def change
    create_table :students do |t|
      t.string :name
      t.string :branch
      t.integer :rollno
      t.float :cgpa
      t.string :college

      t.timestamps
    end
  end
end
