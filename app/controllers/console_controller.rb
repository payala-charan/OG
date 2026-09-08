class ConsoleController < ApplicationController
  def execute
    if request.post?
      @query = params[:query]
      @project_path = params[:project_path]
      if destructive?(@query)
        @warning = true
        @result = "Warning: This query contains destructive operations (update_all, delete_all, destroy_all, drop, truncate) and will not be executed."
      else
        @result = execute_query(@query, @project_path)
      end
    end
  end

  private

  def destructive?(query)
    forbidden = ['update_all', 'delete_all', 'destroy_all', 'drop', 'truncate']
    forbidden.any? { |word| query.downcase.include?(word) }
  end

  def execute_query(query, project_path)
    if project_path.present?
      # Execute in external Rails project using rails runner
      output = `cd "#{project_path}" && rails runner -e development "#{query}" 2>&1`
      output.presence || "Query executed successfully."
    else
      # Execute in current app using eval
      require 'stringio'
      require 'pp'
      old_stdout = $stdout
      $stdout = captured_output = StringIO.new
      begin
        result = eval(query)
        PP.pp(result, captured_output) unless result.nil?
        captured_output.string.presence || "Query executed successfully."
      rescue => e
        "Error: #{e.message}"
      ensure
        $stdout = old_stdout
      end
    end
  end
end