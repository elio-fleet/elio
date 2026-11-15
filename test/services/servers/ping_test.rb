require "test_helper"

class Servers::PingTest < ActiveSupport::TestCase
  include TcpHelpers

  test "reachable? is true when the port accepts connections" do
    with_open_port do |port|
      assert Servers::Ping.reachable?("127.0.0.1", port, timeout: 1)
    end
  end

  test "reachable? is false when the connection is refused" do
    assert_not Servers::Ping.reachable?("127.0.0.1", closed_port, timeout: 1)
  end

  test "reachable? is false when the host cannot be resolved" do
    assert_not Servers::Ping.reachable?("unknown-host.invalid", 22, timeout: 1)
  end

  test "check! records a reachable server" do
    server = servers(:db)

    with_open_port do |port|
      server.update!(host: "127.0.0.1", port: port)
      travel_to Time.zone.local(2026, 10, 3, 12, 0, 0) do
        assert Servers::Ping.check!(server, timeout: 1)
      end
    end

    server.reload
    assert server.reachable
    assert_equal Time.zone.local(2026, 10, 3, 12, 0, 0), server.last_checked_at
  end

  test "check! records an unreachable server" do
    server = servers(:web)
    server.update!(host: "127.0.0.1", port: closed_port)

    assert_not Servers::Ping.check!(server, timeout: 1)

    server.reload
    assert_equal false, server.reachable
    assert_not_nil server.last_checked_at
  end

  test "check! does not change updated_at" do
    server = servers(:web)
    server.update!(host: "127.0.0.1", port: closed_port)

    assert_no_changes -> { server.reload.updated_at } do
      Servers::Ping.check!(server, timeout: 1)
    end
  end

  test "check_all! checks every server and returns the results by server" do
    with_open_port do |open_port|
      servers(:web).update!(host: "127.0.0.1", port: open_port)
      servers(:db).update!(host: "127.0.0.1", port: closed_port)
      servers(:backup).update!(host: "unknown-host.invalid")

      results = Servers::Ping.check_all!(Server.order(:name), timeout: 1)

      assert_equal({ servers(:backup) => false, servers(:db) => false, servers(:web) => true }, results)
    end

    assert servers(:web).reload.reachable
    assert_equal false, servers(:db).reload.reachable
    assert_equal false, servers(:backup).reload.reachable
  end

  test "check_all! returns an empty hash when there are no servers" do
    assert_equal({}, Servers::Ping.check_all!(Server.none))
  end

  test "check! logs a server going down at the second failure in a row" do
    server = servers(:web)
    server.update_columns(host: "127.0.0.1", port: closed_port)

    Servers::Ping.check!(server, timeout: 1)
    assert_empty Activity.all

    Servers::Ping.check!(server, timeout: 1)
    assert_equal [ "server_unreachable" ], Activity.pluck(:kind)
  end
end
