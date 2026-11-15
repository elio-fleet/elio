require "test_helper"

class BackgroundTaskTest < ActiveSupport::TestCase
  include StubHelpers

  def enqueue(servers = [ servers(:web), servers(:db) ], **options, &block)
    BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: servers, user: users(:one), **options, &block)
  end

  test "enqueue! creates a queued item per server and yields them" do
    yielded = []
    task = enqueue { |item| yielded << item.server_name }

    assert_equal "queued", task.status
    assert_equal %w[Database Web], task.items.map(&:server_name)
    assert_equal %w[Database Web], yielded
    assert_equal({ done: 0, total: 2, failed: 0 }, task.progress)
  end

  test "the status follows the items" do
    task = enqueue
    db, web = task.items.to_a

    db.start!
    assert_equal "running", task.reload.status
    assert task.started_at

    db.finish!(:succeeded)
    assert_equal "running", task.reload.status
    assert_nil task.finished_at

    web.start!
    web.finish!(:failed, "Clé refusée")
    task.reload
    assert_equal "partial", task.status
    assert task.finished_at
    assert_equal({ done: 2, total: 2, failed: 1 }, task.progress)
  end

  test "every item succeeded or failed" do
    task = enqueue
    task.items.each { |item| item.finish!(:succeeded) }
    assert_equal "succeeded", task.reload.status

    task = enqueue
    task.items.each { |item| item.finish!(:failed) }
    assert_equal "failed", task.reload.status
  end

  test "a task without items is queued, then done once started" do
    task = enqueue([])
    assert_equal "queued", task.status

    task.start!
    task.refresh!(result: "Rien à faire")
    assert_equal [ "succeeded", "Rien à faire" ], [ task.status, task.result ]
  end

  test "fail! interrupts the unfinished items" do
    task = enqueue
    db, web = task.items.to_a
    db.finish!(:succeeded)

    task.fail!("Erreur interne (RuntimeError)")

    assert_equal [ "failed", "Erreur interne (RuntimeError)" ], [ task.reload.status, task.result ]
    assert_equal [ "succeeded", "failed" ], [ db.reload.status, web.reload.status ]
    assert_equal "Interrompu", web.message
  end

  test "filters, labels and author" do
    queued = enqueue
    failed = enqueue.tap { |task| task.fail!("x") }
    partial = enqueue.tap { |task| task.items.first.finish!(:failed) && task.items.last.finish!(:succeeded) }

    assert_equal [ queued ], BackgroundTask.filtered("queued").to_a
    assert_equal [ failed, partial ].sort_by(&:id), BackgroundTask.filtered("failed").order(:id).to_a
    assert_equal 3, BackgroundTask.filtered("nope").count
    assert_equal [ queued ], BackgroundTask.unfinished.to_a
    assert_equal "Inventaire", queued.kind_label
    assert_equal "yanis@test.fr", BackgroundTask.new(user: User.new(email: "yanis@test.fr")).author_name
    assert_equal "Système", BackgroundTask.new.author_name
  end

  test "validations" do
    task = BackgroundTask.new(kind: "nope", status: "nope", label: "")
    assert_not task.valid?
    assert_equal %i[kind status label], task.errors.attribute_names
  end

  test "expired: finished tasks older than 30 days" do
    old = enqueue.tap { |task| task.fail!("x") && task.update_columns(created_at: 31.days.ago) }
    old_unfinished = enqueue.tap { |task| task.update_columns(created_at: 31.days.ago) }
    enqueue.tap { |task| task.fail!("x") }

    assert_equal [ old ], BackgroundTask.expired.to_a
    PurgeBackgroundTasksJob.perform_now
    assert_not BackgroundTask.exists?(old.id)
    assert BackgroundTask.exists?(old_unfinished.id)
    assert_equal 0, BackgroundTaskItem.where(background_task_id: old.id).count
  end

  test "deleting a server fails its waiting items and keeps its name" do
    task = enqueue
    servers(:web).destroy!

    item = task.items.reload.find_by!(server_name: "Web")
    assert_nil item.server_id
    assert_equal [ "failed", "Serveur supprimé" ], [ item.status, item.message ]
  end

  test "a deleted user leaves the task to the system" do
    task = enqueue
    BackgroundTask.where(id: task.id).update_all(user_id: users(:viewer).id)
    users(:viewer).delete
    assert_equal "Système", task.reload.author_name
  end

  test "the purge runs every day in development and production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[development production].each do |environment|
      assert_equal "PurgeBackgroundTasksJob", recurring.dig(environment, "purge_background_tasks", "class")
    end
  end

  test "a result given as a LocalizedText is read in each reader's language" do
    task = enqueue([])
    task.start!
    task.refresh!(result: LocalizedText.dump("automation.results.reachable", done: 1, count: 2))

    assert_equal I18n.t("automation.results.reachable", done: 1, count: 2, locale: :en), I18n.with_locale(:en) { task.reload.result }
    assert_equal I18n.t("automation.results.reachable", done: 1, count: 2, locale: :fr), task[:result], "plain text kept for the search"
    task.refresh!
    assert task.localized_result, "kept when no result is given"

    task.fail!("boom")
    assert_equal [ "boom", nil ], [ task.result, task.localized_result ]
  end

  test "rerun! starts the run again on its servers, or only on the failed ones" do
    task = enqueue
    db, web = task.items.to_a
    db.finish!(:failed, "Délai dépassé")
    web.finish!(:succeeded)
    jobs = []

    assert task.rerunnable?
    assert task.failures_rerunnable?
    assert_equal :operate, task.rerun_permission

    again = stub_method(Inventory::CollectJob, :perform_later, ->(server, *args, **options) { jobs << [ server.name, args, options[:task_item].background_task_id ] }) do
      task.rerun!(user: users(:operator))
    end
    assert_equal %w[Database Web], again.items.map(&:server_name)
    assert_equal [ [ "Database", [], again.id ], [ "Web", [], again.id ] ], jobs
    assert_equal [ "inventory", users(:operator) ], [ again.kind, again.user ]
    assert_equal "Inventaire (relance)", again.label

    again.items.each { |item| item.finish!(:succeeded) }
    failures = stub_method(Inventory::CollectJob, :perform_later, nil) { task.rerun!(user: users(:operator), only_failed: true) }
    assert_equal %w[Database], failures.items.map(&:server_name)
    assert_equal "Inventaire (échecs relancés, 1 serveur)", failures.label
    assert_equal "Inventaire (failures run again, 1 server)", I18n.with_locale(:en) { failures.label }

    failures.items.each { |item| item.finish!(:failed) }
    nested = stub_method(Inventory::CollectJob, :perform_later, nil) { failures.rerun!(user: users(:operator)) }
    assert_equal "Inventaire (relance)", nested.label, "a run started again keeps the first label"
  end

  test "rerun! leaves out the servers already waiting for the same kind of run" do
    task = enqueue
    task.items.each { |item| item.finish!(:failed) }
    enqueue([ servers(:web) ])

    again = stub_method(Inventory::CollectJob, :perform_later, nil) { task.rerun!(user: users(:one)) }
    assert_equal %w[Database], again.items.map(&:server_name)

    assert_nil stub_method(Inventory::CollectJob, :perform_later, nil) { task.rerun!(user: users(:one)) }, "every server is busy"
  end

  test "what can be started again" do
    unfinished = enqueue
    assert_not unfinished.rerunnable?

    succeeded = enqueue.tap { |task| task.items.each { |item| item.finish!(:succeeded) } }
    assert succeeded.rerunnable?
    assert_not succeeded.failures_rerunnable?

    gone = enqueue([ servers(:backup) ]).tap { |task| task.items.each { |item| item.finish!(:failed) } }
    servers(:backup).destroy!
    assert_not gone.reload.rerunnable?, "no server left"

    import = BackgroundTask.enqueue!(kind: "vulnerabilities", label: "Import", servers: []).tap { |task| task.start! && task.refresh! }
    assert_not import.rerunnable?

    check = BackgroundTask.enqueue!(kind: "key_rotation_check", label: "Simulation", servers: [ servers(:web) ])
    assert_equal :administer, check.rerun_permission
  end

  test "an automation is started again in full, or as an inventory of its failed servers" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "inventory_packages" }
    task = BackgroundTask.enqueue!(kind: "automation", label: LocalizedText.part("automation.kinds.inventory_packages.label"), servers: [ servers(:web), servers(:db) ], automation: automation)
    task.items.find_by!(server_name: "Web").finish!(:failed)
    task.items.find_by!(server_name: "Database").finish!(:succeeded)
    assert_equal :administer, task.rerun_permission
    assert task.failures_rerunnable?

    categories = nil
    failures = stub_method(Inventory::CollectJob, :perform_later, ->(_server, given, **) { categories = given }) { task.rerun!(user: users(:one), only_failed: true) }
    assert_equal [ "inventory", %w[Web], %w[packages] ], [ failures.kind, failures.items.map(&:server_name), categories ]

    again = task.rerun!(user: users(:one))
    assert_equal [ "automation", automation, users(:one) ], [ again.kind, again.automation, again.user ]
    assert_equal again, task.rerun!(user: users(:one)), "the run already waiting"

    servers_ping = Automation.all_kinds.find { |candidate| candidate.kind == "vulnerabilities_update" }
    feeds = BackgroundTask.enqueue!(kind: "automation", label: "Flux", servers: [], automation: servers_ping).tap { |run| run.start! && run.refresh! }
    assert feeds.rerunnable?
    assert_not feeds.failures_rerunnable?
  end

  test "slow servers: more than twice the median and at least 10 seconds" do
    task = enqueue([ servers(:web), servers(:db), servers(:backup) ])
    now = Time.current
    durations = { "Web" => 4, "Database" => 5, "Backup" => 40 }
    task.items.each { |item| item.update!(status: "succeeded", started_at: now - durations.fetch(item.server_name), finished_at: now) }

    assert_equal [ task.items.find_by!(server_name: "Backup").id ], task.slow_item_ids
    assert_equal [], task.slow_item_ids(task.items.first(2)), "too few servers to compare"

    task.items.find_by!(server_name: "Backup").update!(started_at: now - 8)
    assert_equal [], task.reload.slow_item_ids, "under 10 seconds is never slow"
  end

  test "of_kind" do
    inventory = enqueue
    check = BackgroundTask.enqueue!(kind: "key_rotation_check", label: "Simulation", servers: [])
    assert_equal [ check ], BackgroundTask.of_kind("key_rotation_check").to_a
    assert_equal [ inventory, check ].sort_by(&:id), BackgroundTask.of_kind("nope").order(:id).to_a
  end
end
