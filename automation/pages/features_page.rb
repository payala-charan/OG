# automation/pages/features_page.rb
module Pages
  class FeaturesPage
    include Capybara::DSL

    def loaded?
      # Attempt maximize if not already
      begin
        page.driver.browser.manage.window.maximize
        puts "🖥️ Browser window maximized"
      rescue StandardError => e
        puts "⚠️ Could not maximize window: #{e.message}"
      end

      # Verify by path and expected static content on features/index
      has_current_path?(/features/, url: true, wait: 10) && has_content?('Features', wait: 10)
    end

    def print_status
      puts "✅ Features page loaded: #{current_url}" if loaded?
    end

    def visit_feature_path(target_path)
      raise "Feature path is blank" if target_path.nil? || target_path.strip.empty?

      # try to click relevant page link from features grid if visible
      path_token = target_path.gsub(/^\//, '')
      if has_selector?("a[href='#{target_path}']", wait: 2)
        find("a[href='#{target_path}']").click
      elsif has_selector?("a[href*='#{path_token}']", wait: 2)
        find("a[href*='#{path_token}']").click
      else
        # fallback: direct visit when no link in features splash page
        visit target_path
      end

      # ensure we are on expected path
      path_pattern = %r{^https?://.+#{Regexp.escape(target_path)}$}
      unless has_current_path?(path_pattern, url: true, wait: 10)
        raise "❌ Failed to navigate to #{target_path}, current: #{current_url}"
      end

      puts "➡️ Visited feature page: #{target_path}"
    end

    def scroll_page_full
      # smooth scroll down in steps for better user-like visibility
      flow = <<~JS
        const height = document.body.scrollHeight;
        const steps = 30;
        const step = height / steps;
        return new Promise(resolve => {
          let i = 0;
          const scroll = () => {
            window.scrollTo({ top: i * step, behavior: 'smooth' });
            i += 1;
            if (i <= steps) {
              setTimeout(scroll, 120);
            } else {
              setTimeout(resolve, 300);
            }
          };
          scroll();
        });
      JS
      execute_script(flow)
      sleep 0.5

      # pause a moment at bottom
      sleep 1.0

      execute_script('window.scrollTo({ top: 0, behavior: "smooth" })')
      sleep 1.5
      puts "↕️ Completed smooth top-to-bottom-and-back scroll"
    end
  end
end
