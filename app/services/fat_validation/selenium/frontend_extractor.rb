# frozen_string_literal: true

module FatValidation
  module Selenium
    # Reads drug name and Opportunity from #overview-drug-table.
    # Rows are identified by .fa-drug-name, not by position.
    class FrontendExtractor
      DrugRow = Struct.new(:generic_group, :actual_value, :raw_actual, keyword_init: true)
      Overview = Struct.new(:accounting_period_id, :rows, keyword_init: true)

      SCRIPT = <<~JS.freeze
        const table = document.querySelector('#overview-drug-table');
        if (!table) return null;
        const link = table.querySelector('tbody a.fa-table__link');
        let accountingPeriodId = null;
        if (link) {
          try {
            const quarter = new URL(link.getAttribute('href'), window.location.origin).searchParams.get('quarter');
            if (quarter) accountingPeriodId = parseInt(quarter, 10);
          } catch (e) {}
        }
        const rows = [...table.querySelectorAll('tbody tr')].map((tr) => {
          const name = tr.querySelector('.fa-drug-name');
          const amount = tr.querySelector('.fa-opp-cell__amount');
          return {
            generic_group: name ? name.innerText.trim() : '',
            opportunity_text: amount ? amount.innerText.trim() : ''
          };
        });
        return { accounting_period_id: accountingPeriodId, rows: rows };
      JS

      def initialize(driver, environment, wait_seconds: 45)
        @driver = driver
        @environment = environment
        @wait_seconds = wait_seconds
      end

      def extract_overview
        @driver.navigate.to(@environment.overview_url)
        guard_overview_path!

        ::Selenium::WebDriver::Wait.new(timeout: @wait_seconds).until do
          @driver.find_elements(id: "overview-drug-table").any?
        end

        payload = @driver.execute_script(SCRIPT)
        raise MissingReportError, "Overview table was not found." if payload.blank?

        period = payload["accounting_period_id"] || payload[:accounting_period_id]
        raw_rows = payload["rows"] || payload[:rows] || []
        rows = raw_rows.map { |row| drug_row(row) }
        raise EmptyReportError, "Overview table has no drug rows." if rows.empty?
        raise MissingReportError, "Could not read the quarter from the Overview page." if period.blank?

        Overview.new(accounting_period_id: period.to_i, rows: rows)
      rescue ::Selenium::WebDriver::Error::TimeoutError
        raise MissingReportError, "Overview page did not finish loading."
      end

      private

      def drug_row(row)
        raw = row["opportunity_text"] || row[:opportunity_text]
        DrugRow.new(
          generic_group: (row["generic_group"] || row[:generic_group]).to_s.strip,
          actual_value: FatValidation::Money.parse_dollars(raw),
          raw_actual: raw.to_s
        )
      end

      def guard_overview_path!
        path = URI.parse(@driver.current_url.to_s).path.to_s
        return if path.blank? || path == "/overview"
        raise AuthenticationError, "FAT login failed for team #{@environment.team_id}." if path == "/login"

        raise ReadOnlyError, "Stopped because FAT is on #{path}, not Overview."
      rescue URI::InvalidURIError
        raise ReadOnlyError, "Stopped because the FAT page URL was not readable."
      end
    end
  end
end
