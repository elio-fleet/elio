require "test_helper"

class ProblemSinceTest < ActiveSupport::TestCase
  def log(kind, server, at, **data)
    Activity.create!(kind: kind.to_s, server: server, data: data, created_at: at, updated_at: at)
  end

  def disk(percent) = Inventory::HealthStatus.reason("crit", :disk, percent: percent, mount: "/").to_h
  def reboot = Inventory::HealthStatus.reason("warn", :reboot_required).to_h

  # Activities store their data as JSON: string keys, like the server's columns.
  def stored(reason) = reason.deep_stringify_keys

  test "unreachable and refused key: the last time it was lost" do
    web = servers(:web)
    log(:server_unreachable, web, 5.days.ago)
    log(:server_back_online, web, 4.days.ago)
    log(:server_unreachable, web, 2.hours.ago)
    log(:ssh_access_lost, web, 3.days.ago)

    since = ProblemSince.new([ web, servers(:db) ])
    assert_in_delta 2.hours.ago, since.unreachable(web), 1
    assert_in_delta 3.days.ago, since.key_refused(web), 1
    assert_nil since.unreachable(servers(:db))
  end

  test "a reason: the first event of the current run that names it, measures aside" do
    web = servers(:web)
    log(:health_critical, web, 20.days.ago, reasons: [ disk(95) ])
    log(:health_recovered, web, 10.days.ago)
    log(:health_warning, web, 6.days.ago, reasons: [ reboot ])
    log(:health_critical, web, 2.days.ago, reasons: [ disk(91), reboot ], new_reasons: true)

    since = ProblemSince.new([ web ])
    assert_in_delta 2.days.ago, since.reason(web, stored(disk(94)), :health), 1
    assert_in_delta 6.days.ago, since.reason(web, stored(reboot), :health), 1
  end

  test "a reason the journal does not name: the start of the run; nothing logged: nil" do
    web = servers(:web)
    log(:docker_warning, web, 3.days.ago, reasons: [ stored(Inventory::HealthStatus.reason("warn", :images_to_update, count: 1).to_h) ])
    looping = stored(Inventory::HealthStatus.reason("crit", :container_looping, name: "worker").to_h)

    since = ProblemSince.new([ web, servers(:db) ])
    assert_in_delta 3.days.ago, since.reason(web, looping, :docker), 1
    assert_nil since.reason(web, stored(reboot), :health)
    assert_nil since.reason(servers(:db), looping, :docker)
  end

  test "a few queries for the whole fleet" do
    servers = Server.all.to_a
    since = ProblemSince.new(servers)
    queries = 0
    counter = ->(*, payload) { queries += 1 unless payload[:name] == "SCHEMA" }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      servers.each do |server|
        since.unreachable(server)
        since.key_refused(server)
        since.reason(server, stored(reboot), :health)
        since.reason(server, stored(reboot), :docker)
      end
    end
    assert_equal 3, queries
  end
end
