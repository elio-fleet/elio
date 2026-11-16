require "test_helper"

class AuthorizedKeysHelperTest < ActionView::TestCase
  include ApplicationHelper
  setup do
    @blob = Ssh::KeyGenerator.generate.public_key.split.first(2).join(" ")
  end

  def key(options) = AuthorizedKey.parse("#{options} #{@blob}").sole

  test "badges only for the options that restrict the key" do
    assert_empty key_option_badges(key("no-pty,no-agent-forwarding"))

    future = key(%(expiry-time="#{1.day.from_now.utc.strftime("%Y%m%d%H%M")}Z"))
    assert_match "key-option-expiry", key_option_badges(future)
    assert_no_match "key-option-expiry", key_option_badges(future, expiry: false), "already shown by the temporary access"
  end

  test "labels and values in the details" do
    assert_equal "Sans terminal", key_option_label("no-pty")
    assert_equal "tunnel", key_option_label("tunnel")

    utc = key(%(expiry-time="20300102030405Z"))
    assert_match(/2030.* UTC\z/, key_option_value(utc, "expiry-time", "20300102030405Z"))
    local = key(%(expiry-time="203001020304"))
    assert_match(/\(heure locale du serveur\)\z/, key_option_value(local, "expiry-time", "203001020304"))
    assert_equal "10.0.0.1", key_option_value(local, "from", "10.0.0.1")
  end
end
