require "test_helper"

class Inventory::FirstCollectJobTest < ActiveJob::TestCase
  include StubHelpers

  def check_result(success, reason: nil)
    Ssh::Check::Result.new(success: success, message: "m", details: "d", reason: reason)
  end

  def server
    servers(:web).tap { |server| server.update_columns(inventoried_at: nil, ssh_ok: nil) }
  end

  test "collects the inventory when Elio can log in" do
    collected = []
    stub_method(Ssh::Check, :call, check_result(true)) do
      stub_method(Inventory::Collection, :call, ->(server) { collected << server }) { Inventory::FirstCollectJob.perform_now(server) }
    end

    assert_equal [ servers(:web) ], collected
  end

  test "leaves the inventory empty when the key is not installed yet, and remembers the refusal" do
    stub_method(Ssh::Check, :call, check_result(false, reason: :key_refused)) do
      stub_method(Inventory::Collection, :call, ->(*) { flunk "no collection without access" }) { Inventory::FirstCollectJob.perform_now(server) }
    end

    assert_equal false, servers(:web).reload.ssh_ok
    assert_empty servers(:web).inventory_snapshots
  end

  test "an unreachable server is left alone" do
    stub_method(Ssh::Check, :call, check_result(false)) do
      stub_method(Inventory::Collection, :call, ->(*) { flunk "no collection" }) { Inventory::FirstCollectJob.perform_now(server) }
    end

    assert_nil servers(:web).reload.ssh_ok
  end

  test "does nothing for a server already inventoried" do
    servers(:web).update_columns(inventoried_at: Time.current)
    connected = false
    stub_method(Ssh::Check, :call, ->(*) { connected = true }) { Inventory::FirstCollectJob.perform_now(servers(:web)) }

    assert_not connected
  end
end
