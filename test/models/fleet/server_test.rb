require "test_helper"

class ServerTest < ActiveSupport::TestCase
  def build_server(**attributes)
    Server.new({ name: "New", host: "10.0.0.1", username: "deploy" }.merge(attributes))
  end

  test "expected ports: checked, squished, and a port added once" do
    server = servers(:web)
    assert_not server.update(expected_ports: "8081, http")
    assert_includes server.errors[:expected_ports].sole, "http"

    assert server.update(expected_ports: "  ")
    assert_nil server.expected_ports
    assert server.add_expected_port!(8081, "tcp")
    assert server.add_expected_port!(51_820, "udp")
    assert_equal "8081/tcp, 51820/udp", server.reload.expected_ports
    assert_not server.add_expected_port!(8081, "tcp")
    assert server.expected_port_list.include?(51_820, "udp")
  end

  test "fixtures are valid" do
    assert servers(:web).valid?
    assert servers(:db).valid?
    assert servers(:backup).valid?
  end

  test "requires a name, a host and a username" do
    server = build_server(name: "", host: "", username: "")
    assert_not server.valid?
    assert server.errors.added?(:name, :blank)
    assert server.errors.added?(:host, :blank)
    assert server.errors.added?(:username, :blank)
  end

  test "name is unique, case insensitive" do
    server = build_server(name: "web")
    assert_not server.valid?
    assert server.errors.of_kind?(:name, :taken)
  end

  test "the same user on the same host and port is refused once, the host case aside" do
    db = servers(:db)
    server = build_server(host: db.host.upcase, port: db.port, username: db.username)
    assert_not server.valid?
    assert server.errors.of_kind?(:host, :taken)
    assert_includes server.errors.full_messages, "Hôte est déjà utilisé par un autre serveur avec le même port et le même utilisateur"

    assert build_server(host: db.host, port: db.port, username: "other").valid?
    assert build_server(host: db.host, port: 2200, username: db.username).valid?
  end

  test "the database refuses a duplicate address too" do
    db = servers(:db)
    duplicate = build_server(host: db.host.upcase, port: db.port, username: db.username)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "port defaults to 22" do
    assert_equal 22, Server.new.port
  end

  test "port must be an integer between 1 and 65535" do
    [ 0, 65_536, -1, 22.5, nil ].each do |port|
      assert_not build_server(port: port).valid?, "#{port.inspect} should be invalid"
    end
    [ 1, 22, 65_535 ].each do |port|
      assert build_server(port: port).valid?, "#{port} should be valid"
    end
  end

  test "host accepts IPv4, IPv6 and hostnames" do
    [ "192.168.1.11", "::1", "2001:db8::1", "example.com", "srv-01.internal.example.com", "localhost" ].each do |host|
      assert build_server(host: host).valid?, "#{host} should be valid"
    end
  end

  test "host rejects malformed values" do
    [ "not a host", "http://example.com", "-bad.com", "bad_host.com", "user@host" ].each do |host|
      server = build_server(host: host)
      assert_not server.valid?, "#{host} should be invalid"
      assert server.errors.added?(:host, :invalid)
    end
  end

  test "strips whitespace from name, host and username" do
    server = build_server(name: "  Spaced  ", host: " 10.0.0.2 ", username: " deploy ")
    assert_equal "Spaced", server.name
    assert_equal "10.0.0.2", server.host
    assert_equal "deploy", server.username
  end

  test "changing the host or port resets the reachability status" do
    server = servers(:web)
    server.update!(host: "10.0.0.99")
    assert_nil server.reachable
    assert_nil server.last_checked_at

    server = servers(:db)
    server.update!(port: 2200)
    assert_nil server.reachable
    assert_nil server.last_checked_at
  end

  test "changing other attributes keeps the reachability status" do
    server = servers(:web)
    server.update!(name: "Renamed", username: "ops")
    assert server.reachable
    assert_not_nil server.last_checked_at
  end

  test "record_ssh_status! stores the result without touching updated_at" do
    server = servers(:web)

    assert_no_changes -> { server.reload.updated_at } do
      server.record_ssh_status!(true)
    end
    assert server.ssh_ok
    assert_not_nil server.ssh_checked_at
  end

  test "changing the host resets the SSH status too" do
    server = servers(:web)
    server.record_ssh_status!(true)

    server.update!(host: "10.0.0.99")

    assert_nil server.ssh_ok
    assert_nil server.ssh_checked_at
  end

  test "losing SSH access is logged once" do
    server = servers(:web)
    server.record_ssh_status!(false)
    assert_equal 0, Activity.count, "unknown → refused is not a loss"

    server.record_ssh_status!(true)
    server.record_ssh_status!(false)
    server.record_ssh_status!(false)

    assert_equal [ "ssh_access_lost" ], Activity.pluck(:kind)
  end

  test "going down and coming back is logged" do
    server = servers(:web) # reachable in the fixtures

    server.record_reachability!(false)
    server.record_reachability!(false)
    server.record_reachability!(true)
    server.record_reachability!(true)

    assert_equal %w[server_unreachable server_back_online], Activity.order(:id).pluck(:kind)
    assert server.reload.reachable
  end

  test "a port or SSH result is fresh for a few minutes, an SSH failure never" do
    server = servers(:web)
    server.assign_attributes(reachable: false, last_checked_at: 4.minutes.ago, ssh_ok: true, ssh_checked_at: 4.minutes.ago)
    assert server.reachability_fresh?
    assert server.ssh_fresh?

    server.assign_attributes(last_checked_at: 6.minutes.ago, ssh_checked_at: 6.minutes.ago)
    assert_not server.reachability_fresh?
    assert_not server.ssh_fresh?

    server.assign_attributes(reachable: nil, last_checked_at: Time.current, ssh_ok: false, ssh_checked_at: Time.current)
    assert_not server.reachability_fresh?
    assert_not server.ssh_fresh?
  end

  test "a first check that finds the server down is logged" do
    servers(:backup).record_reachability!(false)
    assert_equal [ "server_unreachable" ], Activity.pluck(:kind)
  end

  test "destroying a server deletes its snapshots and temporary accesses, and keeps its activities" do
    server = servers(:web)
    AccountSnapshot.record!(server, AuthorizedKeysAccount.login(server), AuthorizedKey.parse(public_keys(:alice).content))
    TemporaryAccess.create!(server: server, public_key: public_keys(:ci), unix_user: "deploy", key_blob: public_keys(:ci).authorized_key.key,
                            fingerprint: public_keys(:ci).fingerprint, expires_at: 9.minutes.from_now)
    activity = Activity.record!(:key_added, server: server, public_key: public_keys(:alice), unix_user: "deploy")

    server.destroy!

    assert_equal 0, AccountSnapshot.where(server_id: server.id).count
    assert_equal 0, TemporaryAccess.where(server_id: server.id).count
    activity.reload
    assert_nil activity.server_id
    assert_equal "« Alice » ajoutée sur « Web »", activity.summary
  end
end
