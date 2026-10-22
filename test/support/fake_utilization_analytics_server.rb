# frozen_string_literal: true

require "cgi"
require "json"
require "socket"

# Local stand-in for {BASE_URL}/api/utilization_analytics used by the browser test.
class FakeUtilizationAnalyticsServer
  attr_reader :requests

  def initialize
    @requests = []
    @mutex = Mutex.new
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @thread = Thread.new { accept_loop }
  end

  def base_url
    "http://127.0.0.1:#{@port}"
  end

  def stop
    @server.close
  rescue IOError
    nil
  ensure
    @thread&.join(1)
  end

  private

  def accept_loop
    loop do
      client = @server.accept
      handle(client)
    rescue IOError, Errno::EBADF, Errno::EINVAL
      break
    end
  end

  def handle(client)
    request_line = client.gets.to_s
    headers = {}
    while (line = client.gets)
      break if line == "\r\n"
      key, value = line.split(": ", 2)
      headers[key] = value.to_s.strip
    end
    body = headers["Content-Length"].to_i.positive? ? client.read(headers["Content-Length"].to_i).to_s : ""
    _method, target, = request_line.split
    query = target.to_s.include?("?") ? target.split("?", 2).last : body
    params = CGI.parse(query.to_s)
    @mutex.synchronize { @requests << params }
    json = JSON.generate(payload_for(params))
    client.write(
      "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n" \
      "Content-Length: #{json.bytesize}\r\nConnection: close\r\n\r\n#{json}"
    )
  rescue StandardError => error
    warn "Fake utilization analytics server: #{error.message}"
  ensure
    client&.close
  end

  def payload_for(params)
    group = params["group"]&.first
    inpatient = params["charge_class"]&.first == "Inpatient"
    dates = params["start_date"]&.first.present? && params["end_date"]&.first.present?
    quarters = params["quarter_name1"]&.first.present? && params["quarter_name2"]&.first.present?

    if group.present? && quarters && !dates_only?(params)
      comparison_payload(params, inpatient: inpatient, mode: "quarter")
    elsif group.present? && dates && !quarters
      comparison_payload(params, inpatient: inpatient, mode: "date_range")
    else
      filters_payload(params)
    end
  end

  def dates_only?(params)
    params["start_date"]&.first.present? && params["quarter_name1"]&.first.blank?
  end

  def filters_payload(params, mode: "filters")
    {
      "time_period" => params["time_period"]&.first || "quarter",
      "charge_class" => params["charge_class"]&.first || "Outpatient",
      "inpatient" => params["charge_class"]&.first == "Inpatient",
      "mode" => mode,
      "message" => nil,
      "filters" => filter_lists.merge(
        "selected" => selected(params),
        "message" => mode == "filters" ? "Select a group and two periods to view the comparison." : nil
      ),
      "comparison" => nil,
      "trending" => nil
    }
  end

  def comparison_payload(params, inpatient:, mode:)
    margin_visible = !inpatient && mode == "quarter"
    payload = filters_payload(params, mode: mode)
    payload["message"] = nil
    payload["filters"]["message"] = nil
    payload["comparison"] = {
      "periods" => { "baseline" => "Quarter 4 2025", "comparator" => "Quarter 1 2026" },
      "tables_visible" => mode != "date_range",
      "total_units" => {
        "title" => "Total Units",
        "visible" => true,
        "columns" => [ "Brand", "Quarter 4 2025", "Quarter 1 2026", "Total", "Difference" ],
        "rows" => [ row("Zarxio", "10 units", "30 units", "40 units", "20 units") ],
        "grand_total" => row("Total", "B", "C", "API GRAND", "D"),
        "chart" => line_chart("Total Units"),
        "proof" => {
          "charge_classes" => [ "Outpatient", "Emergency", "Inpatient" ],
          "show_inpatient_row_count" => true,
          "rows" => {
            "AVASTIN" => {
              "q1" => { "Outpatient" => 3550.0, "Emergency" => 0.0, "Inpatient" => 0.0 },
              "q2" => { "Outpatient" => 3290.2, "Emergency" => 0.0, "Inpatient" => 0.0 },
              "q1_inpatient_row_count" => 0,
              "q2_inpatient_row_count" => 0,
              "q1_table_total" => 3550.0,
              "q2_table_total" => 3290.2
            }
          },
          "grand_totals" => {
            "q1" => { "cms_units" => 19_108.6 },
            "q2" => { "cms_units" => 17_586.1 }
          }
        }
      },
      "total_margin" => {
        "title" => "Total Margin",
        "visible" => margin_visible,
        "columns" => [ "Brand", "Quarter 4 2025", "Quarter 1 2026", "Total", "Difference" ],
        "rows" => [ row("Zarxio", "1", "2", "3", "4") ],
        "grand_total" => row("Total", "1", "2", "3", "4"),
        "chart" => line_chart("Total Margin").merge("visible" => margin_visible),
        "proof" => nil
      },
      "drug_spend" => {
        "title" => "Drug Spend",
        "visible" => true,
        "y_axis" => "Dollars",
        "x_axis" => "Drug Spend",
        "series" => [
          { "name" => "Baseline", "data" => { "Drug Spend" => 100.0 } },
          { "name" => "Expense Difference", "data" => { "Drug Spend" => 150.5 } }
        ]
      },
      "margin_improvement" => {
        "title" => "Margin Improvement Infliximab",
        "visible" => !inpatient,
        "series" => [ { "name" => "Baseline", "data" => { "MARGIN" => 20.0 } } ]
      }
    }
    if mode == "date_range"
      titles = [ "Units", "Total Product Cost", "Product Cost Per Unit" ]
      titles += [ "Total Margin", "Margin Per Unit" ] unless inpatient
      payload["trending"] = {
        "visible" => true,
        "grain" => "quarterly",
        "charts" => titles.map { |title| line_chart(title) }
      }
    end
    payload
  end

  def row(brand, baseline, comparator, total, difference)
    {
      "brand" => brand,
      "baseline" => 111111,
      "comparator" => 30,
      "total" => 222222,
      "difference" => 4,
      "baseline_display" => baseline,
      "comparator_display" => comparator,
      "total_display" => total,
      "difference_display" => difference
    }
  end

  def line_chart(title)
    {
      "title" => title,
      "visible" => true,
      "y_axis" => title,
      "x_axis" => "Quarter",
      "series" => [
        { "name" => "Zarxio", "data" => [ [ "Quarter 1 2024", 10.25 ], [ "Quarter 2 2024", 30.0 ] ] },
        { "name" => "Total", "data" => [ [ "Quarter 1 2024", 10.25 ], [ "Quarter 2 2024", 30.0 ] ] }
      ]
    }
  end

  def filter_lists
    {
      "generic_name_groups" => [ "Filgrastim", "Infliximab" ],
      "quarters" => [ "Quarter 4 2025", "Quarter 1 2026" ],
      "data_months" => [ "October 2025", "November 2025" ],
      "hospital_names" => [ "Main Campus", "East" ],
      "payor_names" => [ "Aetna" ],
      "charge_classes" => [ "Outpatient", "Inpatient" ]
    }
  end

  def selected(params)
    {
      "group" => params["group"]&.first,
      "time_period" => params["time_period"]&.first || "quarter",
      "quarter_name1" => params["quarter_name1"]&.first || "Quarter 4 2025",
      "quarter_name2" => params["quarter_name2"]&.first || "Quarter 1 2026",
      "data_month1" => params["data_month1"]&.first,
      "data_month2" => params["data_month2"]&.first,
      "start_date" => params["start_date"]&.first,
      "end_date" => params["end_date"]&.first,
      "charge_class" => params["charge_class"]&.first || "Outpatient",
      "hospital_names" => params["hospital_names[]"] || [],
      "payor_names" => params["payor_names[]"] || []
    }
  end
end
