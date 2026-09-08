# frozen_string_literal: true

# Single source of truth for the shared feature explorer.
# Keep this list aligned with the Features dashboard.
class FeatureCatalog
  Category = Struct.new(:id, :name, :icon, :motion, :features, keyword_init: true)
  Feature  = Struct.new(:id, :name, :icon, :path_helper, :kind, :hint, :http_method, keyword_init: true)

  class << self
    def categories
      @categories ||= build_categories
    end

    def feature_count
      @feature_count ||= categories.sum { |category| category.features.size }
    end

    def find_by_path_helper(path_helper)
      categories.each do |category|
        feature = category.features.find { |item| item.path_helper == path_helper }
        return feature if feature
      end
      nil
    end

    private

    def build_categories
      [
        Category.new(
          id: "workspace",
          name: "Workspace",
          icon: "fa-layer-group",
          motion: "orbit",
          features: [
            Feature.new(id: "features", name: "All Features", icon: "fa-th-large", path_helper: :features_path, kind: "home", hint: "Dashboard")
          ]
        ),
        Category.new(
          id: "validation",
          name: "Validation",
          icon: "fa-check-double",
          motion: "pulse",
          features: [
            Feature.new(id: "excel", name: "Excel Validation", icon: "fa-file-excel", path_helper: :validations_path, kind: "task", hint: "Check spreadsheets"),
            Feature.new(id: "rankings", name: "Rankings Validation", icon: "fa-list-ol", path_helper: :ranking_records_path, kind: "task", hint: "Verify rankings"),
            Feature.new(id: "tally", name: "Excel Tally Validation", icon: "fa-balance-scale", path_helper: :tally_validations_path, kind: "task", hint: "Reconcile totals"),
            Feature.new(id: "insurance_pref", name: "Insurance Preference Validator", icon: "fa-shield-alt", path_helper: :insurance_preference_validations_path, kind: "task", hint: "Biosimilar vs master plans")
          ]
        ),
        Category.new(
          id: "pricing",
          name: "Pricing & Products",
          icon: "fa-tags",
          motion: "bounce",
          features: [
            Feature.new(id: "biosimilar", name: "Biosimilar Upload", icon: "fa-file-invoice-dollar", path_helper: :new_biosimilar_prices_path, kind: "task", hint: "Load price files"),
            Feature.new(id: "pricing_catalogs", name: "Pricing Catalogs", icon: "fa-calculator", path_helper: :pricing_catalogs_path, kind: "task", hint: "Compute catalog math"),
            Feature.new(id: "product_rankings", name: "Product Rankings", icon: "fa-trophy", path_helper: :product_rankings_path, kind: "view", hint: "Margin rankings"),
            Feature.new(id: "preference", name: "Product Preferences", icon: "fa-search", path_helper: :product_preference_records_path, kind: "view", hint: "Preference analysis"),
            Feature.new(id: "brand_mapping", name: "Brand Insurance Mapper", icon: "fa-project-diagram", path_helper: :brand_insurance_mappings_path, kind: "task", hint: "Map coverage grids")
          ]
        ),
        Category.new(
          id: "analysis",
          name: "Analysis",
          icon: "fa-chart-line",
          motion: "bars",
          features: [
            Feature.new(id: "payor", name: "Payor Analysis", icon: "fa-chart-bar", path_helper: :payor_preferences_path, kind: "view", hint: "Payor insights"),
            Feature.new(id: "screen", name: "Screen Analysis", icon: "fa-desktop", path_helper: :screen_analyses_path, kind: "task", hint: "Capture screens"),
            Feature.new(id: "schema", name: "Schema Mapping", icon: "fa-sitemap", path_helper: :schema_visualizers_path, kind: "view", hint: "Database map"),
            Feature.new(id: "quarter", name: "Quarter Status", icon: "fa-chart-pie", path_helper: :quarter_statuses_path, kind: "view", hint: "Data coverage")
          ]
        ),
        Category.new(
          id: "files",
          name: "Files",
          icon: "fa-folder-open",
          motion: "float",
          features: [
            Feature.new(id: "storage", name: "Document Storage", icon: "fa-cloud-upload-alt", path_helper: :uploaded_files_path, kind: "task", hint: "Manage uploads"),
            Feature.new(id: "conversion", name: "File Conversion", icon: "fa-exchange-alt", path_helper: :file_conversions_path, kind: "task", hint: "Convert to Excel")
          ]
        ),
        Category.new(
          id: "automation",
          name: "Automation",
          icon: "fa-magic",
          motion: "spin",
          features: [
            Feature.new(id: "automations", name: "Automations", icon: "fa-play-circle", path_helper: :automations_path, kind: "task", hint: "Run workflows"),
            Feature.new(id: "browser_tests", name: "Browser Tests", icon: "fa-vials", path_helper: :run_automation_path, kind: "task", hint: "Run Capybara tests", http_method: :post),
            Feature.new(id: "scheduler", name: "Auto Scheduler", icon: "fa-calendar-alt", path_helper: :automation_schedules_path, kind: "task", hint: "Schedule jobs"),
            Feature.new(id: "alerts", name: "Alert Hub", icon: "fa-bell", path_helper: :alert_emails_path, kind: "task", hint: "Notify teams")
          ]
        ),
        Category.new(
          id: "intelligence",
          name: "Intelligence",
          icon: "fa-brain",
          motion: "wave",
          features: [
            Feature.new(id: "voice", name: "Voice Assistance", icon: "fa-microphone", path_helper: :voice_path, kind: "task", hint: "Ask by voice"),
            Feature.new(id: "github", name: "GitHub Analytics", icon: "fab fa-github", path_helper: :github_path, kind: "view", hint: "Repo insights"),
            Feature.new(id: "console", name: "Rails Console", icon: "fa-terminal", path_helper: :console_path, kind: "task", hint: "Run queries")
          ]
        )
      ].freeze
    end
  end
end
