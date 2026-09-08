module ApplicationHelper
  PUBLIC_EXPLORER_CONTROLLERS = %w[home sessions users].freeze

  def show_feature_explorer?
    logged_in? && PUBLIC_EXPLORER_CONTROLLERS.exclude?(controller_name)
  end

  def explorer_categories
    FeatureCatalog.categories
  end

  def explorer_feature_count
    FeatureCatalog.feature_count
  end

  def explorer_path_for(feature)
    return features_path unless feature&.path_helper && respond_to?(feature.path_helper)

    public_send(feature.path_helper)
  rescue StandardError
    features_path
  end

  def explorer_item_options(feature, category)
    {
      class: "fx-item#{' is-active' if explorer_feature_active?(feature)}",
      data: { explorer_item: feature.id, search: "#{feature.name} #{category.name} #{feature.hint}" },
      aria: { current: (explorer_feature_active?(feature) ? "page" : nil) }
    }
  end

  def explorer_feature_active?(feature)
    return false unless request&.path

    path = explorer_path_for(feature)
    return request.path == path if feature.id == "features"

    request.path == path || request.path.start_with?("#{path}/")
  end

  def explorer_category_active?(category)
    category.features.any? { |feature| explorer_feature_active?(feature) }
  end

  def explorer_user_label
    current_user&.email.to_s.split("@").first.to_s.titleize.presence || "Account"
  end
end

