require "test_helper"

class FeatureCatalogTest < ActiveSupport::TestCase
  test "groups every dashboard feature into a category" do
    assert FeatureCatalog.categories.any?
    assert FeatureCatalog.feature_count >= 20

    FeatureCatalog.categories.each do |category|
      assert category.id.present?
      assert category.name.present?
      assert category.features.any?
    end
  end

  test "every feature path helper is a real route" do
    helper = ApplicationController.helpers

    FeatureCatalog.categories.each do |category|
      category.features.each do |feature|
        assert helper.respond_to?(feature.path_helper),
               "Missing route helper #{feature.path_helper} for #{feature.name}"
        assert helper.public_send(feature.path_helper).present?
      end
    end
  end
end
