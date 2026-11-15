require "test_helper"

class CspReportsControllerTest < ActionDispatch::IntegrationTest
  setup { Throttled::STORE.clear }
  teardown { Throttled::STORE.clear }

  def logged_warnings
    lines = []
    logger = Rails.logger
    fake = ActiveSupport::Logger.new(StringIO.new)
    fake.define_singleton_method(:warn) { |message = nil, &block| lines << (message || block&.call) }
    Rails.logger = fake
    yield
    lines
  ensure
    Rails.logger = logger
  end

  test "a report-uri report is logged, without signing in" do
    report = { "csp-report" => { "document-uri" => "https://elio.test/servers", "violated-directive" => "script-src-elem",
                                 "blocked-uri" => "https://evil.test/x.js", "source-file" => "https://elio.test/servers", "line-number" => 3 } }
    lines = logged_warnings do
      post csp_reports_path, params: report.to_json, headers: { "Content-Type" => "application/csp-report" }
    end
    assert_response :no_content
    assert_equal 1, lines.size
    assert_includes lines.first, 'directive="script-src-elem"'
    assert_includes lines.first, 'blocked="https://evil.test/x.js"'
    assert_includes lines.first, 'source="https://elio.test/servers:3"'
  end

  test "report-to reports are logged, other report types ignored" do
    reports = [ { "type" => "csp-violation", "body" => { "documentURL" => "https://elio.test/", "effectiveDirective" => "style-src-elem", "blockedURL" => "inline" } },
                { "type" => "deprecation", "body" => { "message" => "x" } } ]
    lines = logged_warnings do
      post csp_reports_path, params: reports.to_json, headers: { "Content-Type" => "application/reports+json" }
    end
    assert_response :no_content
    assert_equal [ 'CSP violation: directive="style-src-elem" blocked="inline" page="https://elio.test/"' ], lines
  end

  test "a broken, oversized or odd body is ignored, and fields are cut and kept on one line" do
    lines = logged_warnings do
      post csp_reports_path, params: +"{not json", headers: { "Content-Type" => "application/csp-report" }
      post csp_reports_path, params: { "csp-report" => { "blocked-uri" => "x" * (CspReportsController::MAX_BODY + 10) } }.to_json, headers: { "Content-Type" => "application/csp-report" }
      post csp_reports_path, params: +"42", headers: { "Content-Type" => "application/csp-report" }
      post csp_reports_path, params: { "csp-report" => { "blocked-uri" => "a\nb" + "y" * 300 } }.to_json, headers: { "Content-Type" => "application/csp-report" }
    end
    assert_equal 1, lines.size
    assert_not_includes lines.first, "\n"
    assert_operator lines.first.size, :<, 260
  end

  test "rate-limited per IP" do
    20.times { post csp_reports_path, params: +"{}", headers: { "Content-Type" => "application/csp-report" } }
    assert_response :no_content
    post csp_reports_path, params: +"{}", headers: { "Content-Type" => "application/csp-report" }
    assert_response :too_many_requests
  end
end
