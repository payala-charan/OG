module Pages
  class ConversionUploadPage
    include Capybara::DSL

    def visit_upload_page
      # maximize browser window (ensure full page visibility)
      begin
        page.driver.browser.manage.window.maximize
        puts "🖥️ Browser window maximized"
      rescue StandardError => e
        puts "⚠️ Could not maximize window: #{e.message}"
      end

      visit "/validations"
      puts "📤 Opened upload page: #{current_url}"
    end

    def upload_file(file_path)
      puts "📁 Starting upload flow with file: #{file_path}"

      raise "❌ File not found: #{file_path}" unless File.exist?(file_path)

      visit_upload_page

      # Wait for page to load
      raise "❌ validations page not loaded" unless has_current_path?(/\/validations/, url: true, wait: 10)

      # Click 'Browse Files' to simulate the UX path (optional, not required for attach_file)
      if has_selector?("#browseBtn", wait: 5)
        find("#browseBtn").click
        puts "🖱️ Clicked Browse Files button"
      end

      # Attach file to hidden file input
      attach_file("fileInput", file_path, make_visible: true)
      puts "✅ File attached to input#fileInput"

      # Ensure validate button is available and enabled
      find("#validateBtn", wait: 10)

      # Click Validate button
      find("#validateBtn").click
      puts "🖱️ Clicked Validate Excel File button"

      # Wait for result with 20s total and scroll at 17s
      sleep 17
      puts "⏳ 17 seconds passed. Scrolling to bottom to reveal results."
      execute_script('window.scrollTo(0, document.body.scrollHeight)')

      sleep 3
      puts "⏳ waited additional 3 seconds (total 20s)"

      # Save a result screenshot
      save_screenshot("validation_result.png")
      puts "📸 Screenshot saved: validation_result.png"

      # Final state check
      if has_selector?('.validation-table', wait: 10)
        puts "✅ Validation table is visible"
      elsif has_content?('Validation Errors', wait: 10)
        puts "✅ Validation errors section is visible"
      else
        puts "⚠️ Cannot confirm result section visibility after upload"
      end
    end
  end
end