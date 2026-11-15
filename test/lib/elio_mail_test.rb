require "test_helper"

class ElioMailTest < ActiveSupport::TestCase
  test "sending is enabled by SMTP_ADDRESS" do
    assert Elio::Mail.enabled?("SMTP_ADDRESS" => "smtp.example.com")
    assert_not Elio::Mail.enabled?("SMTP_ADDRESS" => " ")
    assert_not Elio::Mail.enabled?({})
  end

  test "a relay without credentials gets no authentication (Postfix, a local relay)" do
    settings = Elio::Mail.smtp_settings("SMTP_ADDRESS" => "relay.lan", "SMTP_PORT" => "25")
    assert_equal({ address: "relay.lan", port: 25, enable_starttls_auto: true, open_timeout: 5, read_timeout: 10 }, settings)
  end

  test "credentials bring the authentication, plain by default" do
    settings = Elio::Mail.smtp_settings("SMTP_ADDRESS" => "smtp.example.com", "SMTP_USERNAME" => "elio", "SMTP_PASSWORD" => "secret")
    assert_equal [ 587, "elio", "secret", :plain ], settings.values_at(:port, :user_name, :password, :authentication)
    assert_equal :login, Elio::Mail.smtp_settings("SMTP_ADDRESS" => "x", "SMTP_USERNAME" => "u", "SMTP_AUTHENTICATION" => "login")[:authentication]
  end

  test "links in https in production, in http when ELIO_FORCE_SSL=false or outside production" do
    assert_equal "https", Elio::Mail.url_protocol({}, production: true)
    assert_equal "http", Elio::Mail.url_protocol({ "ELIO_FORCE_SSL" => "false" }, production: true)
    assert_equal "http", Elio::Mail.url_protocol({}, production: false)
  end

  test "a password without user name is ignored (no half authentication)" do
    assert_nil Elio::Mail.smtp_settings("SMTP_ADDRESS" => "x", "SMTP_PASSWORD" => "secret")[:password]
  end
end
