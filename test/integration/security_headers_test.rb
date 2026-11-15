require "test_helper"

# The security headers of every page (README, "Security" section).
class SecurityHeadersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "a page carries the strict CSP, its report endpoints and the other headers" do
    sign_in users(:one)
    get root_path
    assert_response :success

    csp = response.headers["Content-Security-Policy"]
    assert_match(/script-src 'self' 'nonce-[^']+'/, csp)
    [ "default-src 'self'", "object-src 'none'", "frame-ancestors 'none'", "form-action 'self'", "base-uri 'self'",
      "report-uri /csp-reports", "report-to csp" ].each { |directive| assert_includes csp, directive }
    assert_equal 'csp="/csp-reports"', response.headers["Reporting-Endpoints"]

    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "SAMEORIGIN", response.headers["X-Frame-Options"]
    assert_equal "strict-origin-when-cross-origin", response.headers["Referrer-Policy"]
    policy = response.headers["Permissions-Policy"]
    %w[camera microphone geolocation payment usb].each { |feature| assert_includes policy, "#{feature}=()" }
  end

  test "the sign in page has them too, and no HSTS over plain HTTP" do
    get new_user_session_path
    assert response.headers["Content-Security-Policy"].present?
    assert response.headers["Permissions-Policy"].present?
    assert_nil response.headers["Strict-Transport-Security"]
  end

  test "HSTS when HTTPS is forced: the header of config.force_ssl, as documented" do
    app = ActionDispatch::SSL.new(->(_env) { [ 200, {}, [ "ok" ] ] })
    _status, headers, _body = app.call(Rack::MockRequest.env_for("https://elio.example.test/"))
    assert_equal "max-age=63072000; includeSubDomains", headers["strict-transport-security"]
  end
end
