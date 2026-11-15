require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  def enqueue(label = "Inventaire du parc", servers: [ servers(:web), servers(:db) ], user: users(:operator))
    BackgroundTask.enqueue!(kind: "inventory", label: label, servers: servers, user: user)
  end

  test "requires to be signed in" do
    get tasks_path
    assert_redirected_to new_user_session_path
  end

  test "lists the tasks, most recent first, for every role" do
    old = enqueue("Ancien").tap { |task| task.items.each { |item| item.finish!(:succeeded) } }
    current = enqueue("Récent")

    sign_in users(:viewer)
    get tasks_path

    assert_response :success
    assert_select "#background-tasks tr.background-task", 2
    assert_select "#background-tasks tr.background-task:first-child a[href=?]", task_path(current), text: "Récent"
    assert_select "##{ActionView::RecordIdentifier.dom_id(current)} [data-status=queued]", text: /À venir/
    assert_select "##{ActionView::RecordIdentifier.dom_id(old)} [data-status=succeeded]", text: /Terminée/
    assert_select "##{ActionView::RecordIdentifier.dom_id(old)} .task-progress", text: %r{2/2}
    assert_select "##{ActionView::RecordIdentifier.dom_id(current)}", text: /operator@/
    assert_select "[data-controller=auto-refresh]", 1, "refreshes while a task is unfinished"
    assert_select "a[href='/jobs']", 0, "the technical view is for admins"
  end

  test "filters by status, with counts" do
    enqueue("En attente")
    enqueue("Cassé").fail!("boom")

    sign_in users(:one)
    get tasks_path(status: "failed")

    assert_select "tr.background-task", 1
    assert_select "tr.background-task", text: /Cassé/
    assert_select "nav.task-filters a[aria-current=true][data-filter=failed]", text: /En échec\s+1/
    assert_select "nav.task-filters a[data-filter=queued]", text: /À venir\s+1/
    assert_select "[data-controller=auto-refresh]", 1
    assert_select "a[href='/jobs']", text: /Suivi technique/
  end

  test "no refresh when everything is finished, and an empty state" do
    sign_in users(:one)
    get tasks_path
    assert_select "[data-controller=auto-refresh]", 0
    assert_select "section", text: /Aucune tâche/
  end

  test "paginates" do
    BackgroundTask.insert_all!(Array.new(TasksController::PER_PAGE + 1) do |index|
      { kind: "inventory", label: "Tâche #{index}", status: "succeeded", created_at: index.minutes.ago, updated_at: Time.current }
    end)
    sign_in users(:one)

    get tasks_path
    assert_select "tr.background-task", TasksController::PER_PAGE
    assert_select "nav.pagination a[rel=next][href=?]", tasks_path(page: 2)

    get tasks_path(page: 2)
    assert_select "tr.background-task", 1
    assert_select "tr.background-task", text: /Tâche #{TasksController::PER_PAGE}/
  end

  test "lists the next automations" do
    automations = Automation.all_kinds.index_by(&:kind)
    automations["inventory_packages"].update!(enabled: true, last_run_at: 1.hour.ago)

    sign_in users(:one)
    get tasks_path

    assert_select "#upcoming-automations li.upcoming-automation", 10 # every collection, enabled by default (not the syncs of disabled extensions)
    assert_select "#upcoming-automations li", text: /Inventaire des paquets.*dans 5 heures/m
    assert_select "#upcoming-automations li", text: /Suivi de la santé.*discrète/m
  end

  test "warns when no worker runs" do
    sign_in users(:one)
    stub_method(JobWorkers, :running?, false) { get tasks_path }
    assert_select ".workers-warning", text: /Aucun worker/

    stub_method(JobWorkers, :running?, true) { get tasks_path }
    assert_select ".workers-warning", 0
  end

  test "a task page shows each server with its result" do
    task = enqueue
    db, web = task.items.to_a
    outcome = ->(status, message = nil) { Inventory::Collector::Outcome.new(status: status, data: {}, message: message) }
    db.finish_inventory!({ "os" => outcome.("ok"), "packages" => outcome.("error", "Délai dépassé") })
    web.start!

    sign_in users(:viewer)
    get task_path(task)

    assert_response :success
    assert_select "h1", "Inventaire du parc"
    assert_select "#task-status[data-status=running]"
    assert_select "#task-items tr.task-item", 2
    assert_select "##{ActionView::RecordIdentifier.dom_id(db)} a[href=?]", server_path(servers(:db)), text: "Database"
    assert_select "##{ActionView::RecordIdentifier.dom_id(db)} [data-status=partial]"
    assert_select "##{ActionView::RecordIdentifier.dom_id(db)} .task-category[data-category=packages]", text: /Paquets : échec/
    assert_select "##{ActionView::RecordIdentifier.dom_id(db)} .task-item-message", "Paquets : Délai dépassé"
    assert_select "##{ActionView::RecordIdentifier.dom_id(web)} [data-status=running]"
    assert_select "[data-controller=auto-refresh]", 1
  end

  test "a finished task with a deleted server and an automation result" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "keys_scan" }
    task = BackgroundTask.enqueue!(kind: "automation", label: "Scan des clés", servers: [ servers(:backup) ], user: nil, automation: automation)
    servers(:backup).destroy!
    task.reload.refresh!(result: "0/1 serveur(s) scanné(s)")

    sign_in users(:one)
    get task_path(task)

    assert_select "#task-status[data-status=failed]"
    assert_select "#task-result", "0/1 serveur(s) scanné(s)"
    assert_select "tr.task-item", text: /Backup\s+\(supprimé\).*Serveur supprimé/m
    assert_select ".task-facts", text: /Système/
    assert_select "[data-controller=auto-refresh]", 0
  end

  test "unknown task" do
    sign_in users(:one)
    get task_path(id: 0)
    assert_response :not_found
  end

  test "the sidebar links to the tasks with the number of unfinished ones" do
    enqueue
    enqueue.fail!("x")

    sign_in users(:viewer)
    get root_path
    assert_select "nav.main-nav a#sidebar-tasks[href=?]", activities_path, text: /Journal\s*1/
  end

  test "searches the tasks by label, server and item message, with the period" do
    inventory = enqueue("Inventaire du parc", servers: [ servers(:web) ])
    inventory.items.first.finish!(:failed, "Connexion refusée par le pare-feu")
    travel_to(10.days.ago) { enqueue("Scan des clés", servers: [ servers(:db) ]) }
    sign_in users(:viewer)

    get tasks_path(q: "pare-feu")
    assert_select "#background-tasks tr.background-task", 1
    assert_select "#background-tasks a[href=?]", task_path(inventory)

    get tasks_path(q: servers(:db).name)
    assert_select "#background-tasks tr.background-task", text: /Scan des clés/

    get tasks_path(q: "Scan", from: 2.days.ago.to_date.iso8601)
    assert_select "#background-tasks tr.background-task", 0
    assert_select "#search-results p", text: "Rien ne correspond à cette recherche."

    get tasks_path(q: "inventaire", status: "failed")
    assert_select ".task-filters a[href=?]", tasks_path(q: "inventaire")
  end

  test "filters by kind, keeping the status and the search" do
    enqueue("Inventaire du parc").fail!("x")
    BackgroundTask.enqueue!(kind: "key_rotation_check", label: "Simulation", servers: []).fail!("x")

    sign_in users(:viewer)
    get tasks_path(kind: "key_rotation_check", status: "failed")

    assert_select "tr.background-task", 1
    assert_select "tr.background-task", text: /Simulation/
    assert_select "nav.task-kinds a[aria-current=true][data-kind=key_rotation_check]"
    assert_select "nav.task-kinds a[data-kind=inventory][href=?]", tasks_path(status: "failed", kind: "inventory")
    assert_select "nav.task-filters a[data-filter=failed]", text: /En échec\s+1/
    assert_select "nav.task-filters a[data-filter=all][href=?]", tasks_path(kind: "key_rotation_check")
    assert_select "form.journal-search input[type=hidden][name=kind][value=key_rotation_check]"

    get tasks_path(kind: "nope")
    assert_select "tr.background-task", 2
  end

  test "no kind filter while every run is of the same kind" do
    enqueue
    sign_in users(:viewer)
    get tasks_path
    assert_select "nav.task-kinds", 0
  end

  test "a finished run offers to start it again, or only its failures, to those allowed" do
    task = enqueue
    task.items.find_by!(server_name: "Web").finish!(:failed, "Délai dépassé")
    task.items.find_by!(server_name: "Database").finish!(:succeeded)

    sign_in users(:operator)
    get task_path(task)
    assert_select "form[action=?] button.task-rerun", task_rerun_path(task), text: /Relancer/
    assert_select "form[action=?][data-turbo-confirm*='le serveur en échec'] button.task-rerun-failed", task_rerun_path(task)
    assert_select "input[name=only_failed][value='1']"

    sign_out users(:operator)
    sign_in users(:viewer)
    get task_path(task)
    assert_select "button.task-rerun", 0
    assert_select "button.task-rerun-failed", 0
  end

  test "starting a run again creates a new run with the failed servers" do
    task = enqueue
    task.items.find_by!(server_name: "Web").finish!(:failed, "Délai dépassé")
    task.items.find_by!(server_name: "Database").finish!(:succeeded)
    sign_in users(:operator)

    assert_difference -> { BackgroundTask.count } do
      stub_method(Inventory::CollectJob, :perform_later, nil) { post task_rerun_path(task), params: { only_failed: "1" } }
    end
    rerun = BackgroundTask.recent.first
    assert_redirected_to task_path(rerun)
    assert_equal [ %w[Web], users(:operator) ], [ rerun.items.map(&:server_name), rerun.user ]
    assert_equal "« Inventaire du parc (échecs relancés, 1 serveur) » lancée.", flash[:notice]

    post task_rerun_path(task), params: { only_failed: "1" }
    assert_redirected_to task_path(task)
    assert_match "déjà traités", flash[:alert]
  end

  test "an unfinished run or one reserved to admins is not started again" do
    task = enqueue
    sign_in users(:operator)
    assert_no_difference -> { BackgroundTask.count } do
      post task_rerun_path(task)
    end
    assert_match "ne peut pas être relancée", flash[:alert]

    check = BackgroundTask.enqueue!(kind: "key_rotation_check", label: "Simulation", servers: [ servers(:web) ])
    check.items.each { |item| item.finish!(:failed) }
    post task_rerun_path(check)
    assert_response :forbidden

    get task_path(check)
    assert_select "button.task-rerun", 0
  end

  test "slow servers are flagged and can come first" do
    task = enqueue("Inventaire", servers: [ servers(:web), servers(:db), servers(:backup) ])
    now = Time.current
    { "Web" => 3, "Database" => 4, "Backup" => 75 }.each do |name, seconds|
      task.items.find_by!(server_name: name).update!(status: "succeeded", started_at: now - seconds, finished_at: now)
    end
    task.refresh!
    backup = task.items.find_by!(server_name: "Backup")

    sign_in users(:viewer)
    get task_path(task)
    assert_select "##{ActionView::RecordIdentifier.dom_id(backup)} .task-slow", text: /lent/
    assert_select ".task-slow", 1
    assert_select "#task-items tr.task-item:first-child", text: /Backup/ # by name
    assert_select "a.task-sort[href=?]", task_path(task, sort: "duration"), text: "Les plus lents d'abord"

    get task_path(task, sort: "duration")
    assert_select "#task-items tr.task-item:first-child", text: /Backup.*1 min 15 s/m
    assert_select "#task-items tr.task-item:last-child", text: /Web/
    assert_select "a.task-sort[href=?]", task_path(task), text: "Par nom"
  end
end
