# Technitium DNS extension in tests: enabled with a fake instance answering
# with the responses recorded on a real Technitium DNS Server 15.6
# (test/fixtures/files/integrations/technitium/); never the network.
module TechnitiumHelpers
  URL = "https://dns.example.test:53443".freeze

  def enable_technitium(**settings)
    Integration.find_or_initialize_by(kind: "technitium").tap do |integration|
      integration.update!(enabled: true, settings: { "url" => URL }.merge(settings.stringify_keys), secrets: { "api_token" => "tt-token" })
    end
  end

  # `routes`: { "/api/…" => body } overriding the recorded answers.
  def fake_technitium(routes = {})
    @technitium_requests = []
    fixture = ->(name) { file_fixture("integrations/technitium/#{name}.json").read }
    stub_method_until_teardown(Integrations::Http, :get, lambda { |url, **options|
      @technitium_requests << [ url, options ]
      uri = URI(url)
      params = URI.decode_www_form(uri.query.to_s).to_h
      next routes[uri.path].respond_to?(:call) ? routes[uri.path].call(params) : routes[uri.path] if routes.key?(uri.path)

      case uri.path
      when "/api/user/session/get" then fixture.("session_get")
      when "/api/zones/list" then fixture.("zones_list")
      when "/api/zones/records/get" then fixture.("records_#{params["zone"]}")
      else raise "unexpected request #{url}"
      end
    })
  end
end
