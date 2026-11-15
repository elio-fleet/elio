require "test_helper"

class NotificationDigestTest < ActiveSupport::TestCase
  setup do
    @digest = NotificationDigest.new(from: 1.hour.ago, to: 1.hour.from_now)
    Activity.record!(:server_unreachable, server: servers(:web))
  end

  test "the highlights follow the typography of the reader's language" do
    I18n.with_locale(:en) do
      assert_includes @digest.lines, "- #{Activity.last.label}: #{Activity.last.summary}"
    end
    I18n.with_locale(:fr) do
      assert_includes NotificationDigest.new(from: 1.hour.ago, to: 1.hour.from_now).lines, "- #{Activity.last.label} : #{Activity.last.summary}"
    end
  end

  test "large counts are written with the separators of the language" do
    assert_equal "12,345", I18n.with_locale(:en) { @digest.number(12_345) }
    assert_equal "12 345", I18n.with_locale(:fr) { @digest.number(12_345) }.tr("  ", "  ")
  end
end
