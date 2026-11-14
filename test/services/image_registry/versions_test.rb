require "test_helper"

class ImageRegistry::VersionsTest < ActiveSupport::TestCase
  TAGS = %w[7.0.10 7.0.11 7.0.15 7.2.4 7.4.6 7.4.6-alpine 7.0.16-alpine 8.0.1 8.2-rc1 7.4.7-rc2 latest 7 7.0 7.0.15-bookworm].freeze

  test "the last fix of the series and the last version of the major, same shape only" do
    assert_equal({ patch: "7.0.15", major: "7.4.6" }, ImageRegistry::Versions.newer("7.0.11", TAGS))
    assert_equal({ major: "7.4.6" }, ImageRegistry::Versions.newer("7.0.15", TAGS), "already the last fix")
    assert_equal({}, ImageRegistry::Versions.newer("7.4.6", TAGS), "never a new major (8.0.1), never a pre-release (7.4.7-rc2)")
    assert_equal({ patch: "7.0.16-alpine", major: "7.4.6-alpine" }, ImageRegistry::Versions.newer("7.0.11-alpine", TAGS), "the same variant")
  end

  test "only version tags are compared" do
    %w[latest 7 bookworm 2.4 v1.2.3 3.11.4-slim-bookworm].each { |tag| assert_equal tag != "latest" && tag != "7" && tag != "bookworm", ImageRegistry::Versions.version_tag?(tag), tag }
    assert_equal({}, ImageRegistry::Versions.newer("latest", TAGS))
    assert_not ImageRegistry::Versions.version_tag?("8.2-rc1")
  end
end
