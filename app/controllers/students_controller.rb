class StudentsController < ApplicationController
  require 'roo'

  def index
    @students = Student.all
  end

  def upload
    file = params[:file]

    if file.nil?
      redirect_to root_path, alert: "Please select a file"
      return
    end

    # Open the Excel file
    spreadsheet = Roo::Spreadsheet.open(file.path)

    header = spreadsheet.row(1).map { |h| h.to_s.strip.downcase }  # ["Name", "Branch", "Rollno", "cgpa", "College"]

    (2..spreadsheet.last_row).each do |i|
      row = Hash[[header, spreadsheet.row(i)].transpose]
      Student.create(
        name: row["name"],
        branch: row["branch"],
        rollno: row["rollno"],
        cgpa: row["cgpa"],
        college: row["college"]
      )
    end

    redirect_to root_path, notice: "Students imported successfully!"
  end
end
