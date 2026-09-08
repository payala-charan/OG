# automation/pages/home_page.rb
module Pages
  class HomePage
    include Capybara::DSL

    def visit_home
      begin
        page.driver.browser.manage.window.maximize
        puts "🖥️ Browser window maximized"
      rescue StandardError => e
        puts "⚠️ Could not maximize window: #{e.message}"
      end

      visit '/'
      puts "📄 Opened home page: #{current_url}"
    end

    def go_to_sign_in
      if has_link?('Sign In', wait: 10)
        click_link 'Sign In'
      elsif has_link?('Sign in', wait: 10)
        click_link 'Sign in'
      elsif has_link?('Login', wait: 10)
        click_link 'Login'
      else
        # fallback to known path selector, if nav item text uses custom markup
        if has_selector?('a[href="/login"]', wait: 10)
          find('a[href="/login"]').click
        else
          raise "Unable to find Sign In link/button on home page"
        end
      end
      puts "➡️ Navigated to sign in page: #{current_url}"
    end
  end
end
