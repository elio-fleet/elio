# Gandi extension in tests: enabled with a fake API v5 answering with the
# examples of its documentation (test/fixtures/files/integrations/gandi/);
# never the network.
module GandiHelpers
  def enable_gandi(**settings)
    Integration.find_or_initialize_by(kind: "gandi").tap do |integration|
      integration.update!(enabled: true, settings: settings.stringify_keys, secrets: { "api_token" => "pat_test-123" })
    end
  end

  # `routes`: { "/v5/…" => body or ->(params) { body } } overriding the examples.
  def fake_gandi(routes = {}, expires_in: 10.days)
    @gandi_requests = []
    fixture = ->(name) { file_fixture("integrations/gandi/#{name}.json").read }
    stub_method_until_teardown(Integrations::Http, :get, lambda { |url, **options|
      @gandi_requests << [ url, options ]
      uri = URI(url)
      params = URI.decode_www_form(uri.query.to_s).to_h
      next routes[uri.path].respond_to?(:call) ? routes[uri.path].call(params) : routes[uri.path] if routes.key?(uri.path)
      next "[]" if params["page"].to_i > 1

      case uri.path
      when "/v5/livedns/domains" then fixture.("livedns_domains")
      when %r{\A/v5/livedns/domains/([^/]+)/records\z} then fixture.("records_#{$1}")
      when "/v5/domain/domains" then fixture.("domains").sub("REPLACE_SOON", expires_in.from_now.iso8601).sub("REPLACE_SOON", expires_in.from_now.iso8601).sub("REPLACE_LATER", 200.days.from_now.iso8601)
      else raise "unexpected request #{url}"
      end
    })
  end
end
