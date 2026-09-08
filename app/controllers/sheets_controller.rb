class SheetsController < ApplicationController
  require 'roo'

  def index
  end

  def upload
    file = params[:file]

    if file.nil?
      redirect_to root_path, alert: "Please select a file"
      return
    end

    # Read Excel
    spreadsheet = Roo::Spreadsheet.open(file.path)
    header = spreadsheet.row(1)
    @data = []

    (2..spreadsheet.last_row).each do |i|
      row = Hash[[header, spreadsheet.row(i)].transpose]

      name = row["A"] || row["Name"]
      b = row["B"].to_f
      c = row["C"].to_f
      d = row["D"].to_f
      e = row["E"].to_f
      f = row["F"].to_f

      expected_d = c + b
      expected_e = c - b

      d_status = (d == expected_d) ? "Yes" : "No"
      e_status = (e == expected_e) ? "Yes" : "No"

      name_match = NameMatch.find_by(name: name.downcase)
      if name_match.present?
        expected_f = b * name_match.corresponding_value
        f_status = (f == expected_f) ? "Yes" : "No"
      else
        expected_f = nil
        f_status = "Name not found"
      end

      @data << {
        name: name,
        b: b, c: c, d: d, e: e,
        expected_d: expected_d,
        expected_e: expected_e,
        d_status: d_status,
        e_status: e_status,
        f_status: f_status
      }
    end
  end
end
