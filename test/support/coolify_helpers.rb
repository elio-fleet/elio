# Coolify extension in tests: enabled with connections to a fake API v1
# (test/fixtures/files/integrations/coolify/team_<name>.json: one team per
# token, the shape of a real Coolify 4.6.0 answer, anonymized); never the network.
module CoolifyHelpers
  TOKENS = { "tok-tools" => "team_tools", "tok-maps" => "team_maps" }.freeze

  def enable_coolify(*tokens, url: "https://coolify.example.com")
    tokens = [ "tok-tools" ] if tokens.empty?
    Integration.find_or_initialize_by(kind: "coolify").tap do |integration|
      integration.update!(enabled: true)
      tokens.each { |token| integration.connections.create!(settings: { "url" => url }, secrets: { "token" => token }) }
    end
  end

  # `routes`: { "team_tools" => { "/servers" => body } } overriding the fixtures.
  def fake_coolify(routes = {})
    @coolify_requests = []
    stub_method_until_teardown(Integrations::Http, :get, lambda { |url, **options|
      @coolify_requests << [ url, options ]
      token = options.dig(:headers, "Authorization").to_s.delete_prefix("Bearer ")
      team = TOKENS[token] or raise Integrations::Error, "Coolify a refusé l'accès (code 401)"
      path = URI(url).path.delete_prefix("/api/v1")
      answers = JSON.parse(file_fixture("integrations/coolify/#{team}.json").read).merge(routes.fetch(team, {}))
      raise "unexpected request #{url}" unless answers.key?(path)

      answer = answers[path]
      answer.is_a?(String) ? answer : JSON.generate(answer)
    })
  end
end
