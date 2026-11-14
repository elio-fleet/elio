# Content Security Policy (AUDIT.md S1): scripts only from Elio itself, with
# a per-request nonce for the importmap and the theme script; no plugins, no
# framing, forms only towards Elio. `style=` attributes stay allowed (gauge
# widths, set by the server), <style> elements need the nonce (Turbo's
# progress bar reads it from csp_meta_tag).
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self
    policy.style_src :self
    policy.style_src_attr :unsafe_inline
    policy.img_src :self, :data
    policy.font_src :self, :data
    policy.connect_src :self
    policy.object_src :none
    policy.base_uri :self
    policy.form_action :self
    policy.frame_ancestors :none
    # Violations reported to Elio itself only (CspReportsController, logged):
    # report-uri for every browser, report-to (Reporting-Endpoints below) for
    # those that prefer it. Never an external endpoint.
    policy.report_uri "/csp-reports"
    policy.directives["report-to"] = [ "csp" ]
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end

# Other security headers, on every response (Rails already sends
# X-Content-Type-Options, X-Frame-Options and Referrer-Policy):
# - Reporting-Endpoints: where report-to sends the CSP violations;
# - Permissions-Policy: Elio uses no camera, microphone, location, payment or
#   device API, so no page (nor an injected script) can ask for them.
# Strict-Transport-Security comes with config.force_ssl (production, unless
# ELIO_FORCE_SSL=false): never over plain HTTP, where it would mean nothing.
Rails.application.config.action_dispatch.default_headers.merge!(
  "Reporting-Endpoints" => 'csp="/csp-reports"',
  "Permissions-Policy" => %w[accelerometer camera display-capture geolocation gyroscope hid magnetometer microphone
                             midi payment serial usb].map { |feature| "#{feature}=()" }.join(", ")
)
