require "test_helper"

class Servers::ExtensionCandidatesTest < ActiveSupport::TestCase
  def enable(kind) = Integration.find_or_create_by!(kind: kind).tap { |integration| integration.update_column(:enabled, true) }

  def coolify_connection
    enable("coolify").connections.create!(settings: { "url" => "https://coolify.example.test" }, secrets: { "token" => "t" })
  end

  test "nothing when the extensions are disabled, even with data left" do
    OvhResource.create!(kind: "vps", external_id: "vps-1", name: "vps-1", addresses: [ "203.0.113.20" ])

    assert_empty Servers::ExtensionCandidates.call
  end

  test "OVHcloud services not attached to a server, on their public IPv4" do
    enable("ovh")
    OvhResource.create!(kind: "dedicated", external_id: "ns1.ip-1-2-3.eu", name: "ns1.example.net", data: { "ip" => "203.0.113.10" }, addresses: [ "2001:db8::/64" ])
    OvhResource.create!(kind: "instance", external_id: "p/i", name: "worker", addresses: [ "2001:db8::1", "10.1.0.4", "198.51.100.7" ])
    OvhResource.create!(kind: "vps", external_id: "vps-2", name: "attached", addresses: [ "203.0.113.30" ], server: servers(:web))
    OvhResource.create!(kind: "ip", external_id: "203.0.113.40/32", name: "203.0.113.40/32", addresses: [ "203.0.113.40" ])

    assert_equal [ [ "OVHcloud", "ns1.example.net", "203.0.113.10", nil, nil ], [ "OVHcloud", "worker", "198.51.100.7", nil, nil ] ],
                 Servers::ExtensionCandidates.call.map { |candidate| candidate.to_h.values }
  end

  test "Coolify servers not attached, with their port and user, without the local host; one row per address" do
    enable("ovh")
    OvhResource.create!(kind: "vps", external_id: "vps-1", name: "vps-1", addresses: [ "203.0.113.20" ])
    connection = coolify_connection
    CoolifyResource.create!(connection: connection, kind: "server", uuid: "s1", name: "builder", data: { "ip" => "203.0.113.21", "port" => 2222, "user" => "deploy" })
    CoolifyResource.create!(connection: connection, kind: "server", uuid: "s2", name: "localhost", data: { "ip" => "host.docker.internal", "port" => 22, "user" => "root" })
    CoolifyResource.create!(connection: connection, kind: "server", uuid: "s3", name: "same", data: { "ip" => "203.0.113.20", "port" => 22, "user" => "root" })
    CoolifyResource.create!(connection: connection, kind: "server", uuid: "s4", name: "web", data: { "ip" => "192.168.1.10" }, server: servers(:web))

    candidates = Servers::ExtensionCandidates.call

    assert_equal [ "vps-1", "builder" ], candidates.map(&:name)
    assert_equal [ "Coolify", "203.0.113.21", 2222, "deploy" ], candidates.last.to_h.values_at(:source, :host, :port, :username)
  end

  test "as CSV, read back by the import" do
    candidates = [ Servers::ExtensionCandidates::Candidate.new("Coolify", "builder, eu", "203.0.113.21", 2222, "deploy"),
                   Servers::ExtensionCandidates::Candidate.new("OVHcloud", "vps-1", "203.0.113.20", nil, nil) ]

    rows = Servers::Import.parse(Servers::ExtensionCandidates.csv(candidates), format: "csv", default_username: "debian")

    assert_equal [ [ "builder, eu", "203.0.113.21", 2222, "deploy" ], [ "vps-1", "203.0.113.20", 22, "debian" ] ], rows.map { |row| [ row.name, row.host, row.port, row.username ] }
    assert rows.all?(&:valid?)
  end
end
