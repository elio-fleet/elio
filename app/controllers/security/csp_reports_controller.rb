# Receives the Content Security Policy violation reports of the browsers
# (report-uri and report-to, see config/initializers/content_security_policy.rb)
# and writes them to the log: a violation means a page of Elio breaks its own
# policy, or something tried to inject a script. Elio's own address only,
# never an external service.
#
# Browsers send the reports without the session, so no sign in here; the body
# is capped, the requests are rate-limited per IP, and nothing is stored in
# the database (a flood can only add log lines, a few per minute).
class CspReportsController < ActionController::API
  MAX_BODY = 8.kilobytes
  MAX_REPORTS = 5
  MAX_FIELD = 200

  rate_limit to: 20, within: 1.minute, store: Throttled::STORE, name: "csp_reports", with: -> { head :too_many_requests }

  def create
    reports.first(MAX_REPORTS).each { |report| Rails.logger.warn("CSP violation: #{summary(report)}") }
    head :no_content
  end

  private

  # The reports of the body, as hashes: report-uri sends {"csp-report": {…}}
  # (application/csp-report), report-to an array of {"type", "body": {…}}
  # (application/reports+json). Anything else is ignored.
  def reports
    data = JSON.parse(request.body.read(MAX_BODY + 1).to_s)
    entries = data.is_a?(Array) ? data.filter_map { |entry| entry["body"] if entry.is_a?(Hash) && entry["type"] == "csp-violation" } : [ data["csp-report"] ]
    entries.grep(Hash)
  rescue JSON::ParserError, NoMethodError, TypeError
    []
  end

  # One line: directive, blocked address, page (both spellings of the keys).
  def summary(report)
    {
      directive: report["effectiveDirective"] || report["effective-directive"] || report["violated-directive"],
      blocked: report["blockedURL"] || report["blocked-uri"],
      page: report["documentURL"] || report["document-uri"],
      source: [ report["sourceFile"] || report["source-file"], report["lineNumber"] || report["line-number"] ].compact.join(":").presence
    }.compact_blank.map { |key, value| "#{key}=#{value.to_s.gsub(/[[:cntrl:]]/, " ").truncate(MAX_FIELD).inspect}" }.join(" ")
  end
end
