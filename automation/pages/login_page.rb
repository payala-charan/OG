module Pages
  class LoginPage
    include Capybara::DSL

    def login(email, password)
      puts "🔐 Starting login process..."

      begin
        page.driver.browser.manage.window.maximize
        puts "🖥️ Browser window maximized"
      rescue StandardError => e
        puts "⚠️ Could not maximize window: #{e.message}"
      end

      # 1. Visit login page
      visit "/login"
      puts "🌐 Visited URL: #{current_url}"

      # 2. Take screenshot before doing anything
      save_screenshot("before_login.png")
      puts "📸 Screenshot saved: before_login.png"

      # 3. Print all input fields (VERY IMPORTANT DEBUG)
      puts "🔍 Listing all input fields on page:"
      all("input").each do |input|
        puts "👉 ID: #{input[:id]}, NAME: #{input[:name]}, TYPE: #{input[:type]}"
      end

      # 4. Wait for email field
      puts "⏳ Waiting for email field..."
      find("#email", wait: 15)

      # 5. Fill email & password
      puts "✍️ Filling login credentials..."
      find("#email").set(email)
      find("#password").set(password)

      # 6. Take screenshot after filling
      save_screenshot("after_filling.png")
      puts "📸 Screenshot saved: after_filling.png"

      # 7. Click login button
      puts "🖱️ Clicking Login button..."
      click_button "Login Now"

      # 8. Wait for navigation / success indicator
      sleep 5   # temporary wait (can improve later)

      # 9. Final screenshot
      save_screenshot("after_login.png")
      puts "📸 Screenshot saved: after_login.png"

      # 10. Print final URL
      puts "✅ After login URL: #{current_url}"

      puts "🎉 Login process completed!"
    end
  end
end