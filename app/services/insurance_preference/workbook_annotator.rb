# frozen_string_literal: true

require "json"
require "open3"
require "tempfile"

module InsurancePreference
  class WorkbookAnnotator
    Error = Class.new(StandardError)
    PYTHON_SCRIPT = Rails.root.join("lib/scripts/annotate_insurance_preference.py")
    COLORS = {
      "black" => "FF000000",
      "red" => "FFFF0000",
      "yellow" => "FFFFC000"
    }.freeze

    def initialize(input_path, annotations)
      @input_path = input_path
      @annotations = annotations
    end

    def call(output_path)
      if python_available?
        write_with_python(output_path)
      else
        write_with_rubyxl(output_path)
      end
      output_path
    rescue Error
      write_with_rubyxl(output_path)
      output_path
    end

    def self.python_available?
      return @python_available if defined?(@python_available)

      @python_available = begin
        _out, status = Open3.capture2e("python3", "-c", "import openpyxl")
        status.success?
      rescue Errno::ENOENT, Errno::EACCES
        false
      end
    end

    def python_available?
      self.class.python_available?
    end

    def collect_formula_snapshot(path)
      require "rubyXL"
      book = RubyXL::Parser.parse(path)
      formulas = {}
      book.worksheets.each do |ws|
        ws.each do |row|
          next unless row

          row.cells.compact.each do |cell|
            next unless cell.formula

            formulas["#{ws.sheet_name}!#{FormulaShifter.column_letters(cell.column + 1)}#{cell.row + 1}"] = cell.formula
          end
        end
      end
      formulas
    end

    private

    def write_with_python(output_path)
      payload = {
        "input_path" => @input_path.to_s,
        "output_path" => output_path.to_s,
        "column_name" => @annotations[:column_name] || Config::CLAUDE_COLUMN_NAME,
        "sheets" => @annotations[:sheets]
      }
      stdout, stderr, status = Open3.capture3("python3", PYTHON_SCRIPT.to_s, stdin_data: JSON.generate(payload))
      unless status.success?
        raise Error, "Python annotator failed: #{stderr.presence || stdout}"
      end
    end

    def write_with_rubyxl(output_path)
      require "rubyXL"
      require "rubyXL/convenience_methods/cell"
      require "rubyXL/convenience_methods/workbook"
      require "rubyXL/convenience_methods/worksheet"

      FileUtils.cp(@input_path, output_path)
      book = RubyXL::Parser.parse(output_path)
      column_name = @annotations[:column_name] || Config::CLAUDE_COLUMN_NAME

      Array(@annotations[:sheets]).each do |sheet_spec|
        ws = book[sheet_spec["name"] || sheet_spec[:name]]
        next unless ws

        insert_col = (sheet_spec["insert_col"] || sheet_spec[:insert_col]).to_i
        header_row = (sheet_spec["header_row"] || sheet_spec[:header_row] || 1).to_i
        insert_column(ws, insert_col)
        rewrite_formulas(ws, insert_col)
        header = ws.add_cell(header_row - 1, insert_col - 1, column_name)
        header.change_font_bold(true) if header.respond_to?(:change_font_bold)

        Array(sheet_spec["cells"] || sheet_spec[:cells]).each do |cell_spec|
          runs = cell_spec["runs"] || cell_spec[:runs] || []
          row_idx = (cell_spec["row"] || cell_spec[:row]).to_i - 1
          col_idx = insert_col - 1
          if runs.empty?
            ws.add_cell(row_idx, col_idx, nil)
          else
            write_rich_text(ws, row_idx, col_idx, runs)
          end
        end
      end

      book.write(output_path)
    end

    def insert_column(ws, insert_col)
      insert_idx = insert_col - 1
      max_col = 0
      ws.sheet_data.rows.each do |row|
        next unless row

        row.cells.each_with_index do |cell, idx|
          max_col = idx if cell && idx > max_col
        end
      end

      (max_col).downto(insert_idx) do |col|
        ws.sheet_data.rows.each do |row|
          next unless row

          cell = row[col]
          next unless cell

          new_cell = Marshal.load(Marshal.dump(cell))
          new_cell.column = col + 1 if new_cell.respond_to?(:column=)
          row.cells[col + 1] = new_cell
        end
        copy_column_width(ws, col, col + 1)
      end

      ws.sheet_data.rows.each do |row|
        next unless row

        row.cells[insert_idx] = nil
      end
    end

    def copy_column_width(ws, from_idx, to_idx)
      return unless ws.cols

      source = ws.cols.find { |col| col && col.min && from_idx + 1 >= col.min && from_idx + 1 <= col.max }
      return unless source

      ws.change_column_width(to_idx, source.width) if ws.respond_to?(:change_column_width) && source.width
    rescue StandardError
      nil
    end

    def rewrite_formulas(ws, insert_col)
      ws.sheet_data.rows.each do |row|
        next unless row

        row.cells.compact.each do |cell|
          next unless cell.formula

          cell.formula = FormulaShifter.shift_formula(cell.formula, insert_col)
        end
      end
    end

    def write_rich_text(ws, row_idx, col_idx, runs)
      cell = ws.add_cell(row_idx, col_idx, runs.map { |run| run["text"] || run[:text] }.join)
      rich = RubyXL::RichText.new
      rich.r = runs.map do |run|
        color = COLORS[run["color"] || run[:color]] || COLORS["black"]
        RubyXL::RichTextRun.new(
          rPr: RubyXL::RunProperties.new(color: RubyXL::Color.new(rgb: color)),
          t: RubyXL::Text.new(value: (run["text"] || run[:text]).to_s)
        )
      end
      cell.is = rich
      cell.datatype = RubyXL::DataType::RAW_STRING
      cell
    end
  end
end
