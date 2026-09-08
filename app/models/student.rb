class Student < ApplicationRecord
  validates :name, :branch, :rollno, :cgpa, :college, presence: true
  validates :rollno, uniqueness: true
end
