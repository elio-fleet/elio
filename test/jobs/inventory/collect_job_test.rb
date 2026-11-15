require "test_helper"

class Inventory::CollectJobTest < ActiveJob::TestCase
  include StubHelpers

  test "collects every category, or the given ones" do
    calls = []
    stub_method(Inventory::Collection, :call, ->(server, **options) { calls << [ server, options ] }) do
      Inventory::CollectJob.perform_now(servers(:web))
      Inventory::CollectJob.perform_now(servers(:web), %w[os])
    end

    assert_equal [ [ servers(:web), {} ], [ servers(:web), { categories: %w[os] } ] ], calls
  end

  test "reports to its task item: partial when a category fails" do
    task = BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: [ servers(:web) ], user: users(:one))
    item = task.items.sole
    outcome = ->(status, message = nil) { Inventory::Collector::Outcome.new(status: status, data: {}, message: message) }
    outcomes = { "os" => outcome.("ok"), "ports" => outcome.("partial", "Sans accès root"), "packages" => outcome.("error", "Délai dépassé") }

    stub_method(Inventory::Collection, :call, outcomes) { Inventory::CollectJob.perform_now(servers(:web), task_item: item) }

    item.reload
    assert_equal "partial", item.status
    assert_equal "Ports : Sans accès root · Paquets : Délai dépassé", item.message
    assert_equal({ "status" => "error", "message" => "Délai dépassé" }, item.details["packages"])
    assert item.started_at && item.finished_at
    assert_equal "partial", task.reload.status
  end

  test "every category failing fails the item, a crash too" do
    task = BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: [ servers(:web), servers(:db) ], user: nil)
    web, db = task.items.sort_by(&:server_name).reverse
    failed = %w[os ports].index_with { Inventory::Collector::Outcome.new(status: "error", data: {}, message: "Clé refusée") }

    stub_method(Inventory::Collection, :call, failed) { Inventory::CollectJob.perform_now(servers(:web), task_item: web) }
    assert_equal [ "failed", "Clé refusée" ], [ web.reload.status, web.message ], "the same error is said once"
    assert_equal "running", task.reload.status, "the other server is still queued"

    stub_method(Inventory::Collection, :call, ->(*) { raise "boom" }) do
      assert_raises(RuntimeError) { Inventory::CollectJob.perform_now(servers(:db), task_item: db) }
    end
    assert_equal [ "failed", "Erreur interne (RuntimeError)" ], [ db.reload.status, db.message ]
    assert_equal "failed", task.reload.status
    assert task.finished_at
  end

  test "a server called off while it waited is not collected" do
    task = BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: [ servers(:web) ], user: users(:one))
    task.cancel!

    stub_method(Inventory::Collection, :call, ->(*) { flunk "collected" }) { Inventory::CollectJob.perform_now(servers(:web), task_item: task.items.sole) }

    assert_equal [ "failed", "Annulé" ], [ task.items.sole.reload.status, task.items.sole.message ]
  end
end
