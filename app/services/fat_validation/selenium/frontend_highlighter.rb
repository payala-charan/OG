# frozen_string_literal: true

module FatValidation
  module Selenium
    # Paints green or red on Opportunity cells. Style only: no clicks and no submits.
    class FrontendHighlighter
      SCRIPT = <<~JS.freeze
        const rows = JSON.parse(arguments[0]);
        let style = document.getElementById('og-fv-style');
        if (!style) {
          style = document.createElement('style');
          style.id = 'og-fv-style';
          style.textContent = '.og-fv-pass{background:#bbf7d0 !important}.og-fv-fail{background:#fecaca !important}.fa-opp-cell__amount.og-fv-pass{background:#16a34a !important;color:#052e16 !important;border-radius:6px;padding:2px 8px}.fa-opp-cell__amount.og-fv-fail{background:#dc2626 !important;color:#fff !important;border-radius:6px;padding:2px 8px}';
          document.head.appendChild(style);
        }
        const byName = {};
        rows.forEach((row) => { byName[row.generic_group] = row.status; });
        document.querySelectorAll('#overview-drug-table tbody tr').forEach((tr) => {
          const nameNode = tr.querySelector('.fa-drug-name');
          const cell = tr.querySelector('.fa-table__td--opp');
          if (!nameNode || !cell) return;
          const status = byName[nameNode.innerText.trim()];
          if (!status) return;
          const pass = status === 'PASS';
          const amount = cell.querySelector('.fa-opp-cell__amount') || cell;
          amount.style.setProperty('background-color', pass ? '#16a34a' : '#dc2626', 'important');
          amount.style.setProperty('color', pass ? '#052e16' : '#ffffff', 'important');
          amount.style.setProperty('border-radius', '6px', 'important');
          amount.style.setProperty('padding', '2px 8px', 'important');
          cell.style.setProperty('background-color', pass ? '#bbf7d0' : '#fecaca', 'important');
        });
        const firstFail = document.querySelector('#overview-drug-table .og-fv-fail');
        if (firstFail) firstFail.scrollIntoView({ block: 'center' });
        return true;
      JS

      def initialize(driver)
        @driver = driver
      end

      def apply(comparisons)
        payload = comparisons.map do |row|
          { "generic_group" => row[:generic_group].to_s, "status" => row[:status].to_s }
        end
        @driver.execute_script(SCRIPT, payload.to_json)
      rescue ::Selenium::WebDriver::Error::WebDriverError => e
        raise BrowserError, "Could not highlight the Overview table (#{e.class.name.demodulize})."
      end
    end
  end
end
