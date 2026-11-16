require "test_helper"

class ScheduledTasksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  NOW = Time.zone.at(1_762_000_000)

  def collect(server, fixture: :debian13, status: "ok", message: nil)
    data = Inventory::Collectors::ScheduledTasks.parse(file_fixture("inventory/scheduled_tasks/#{fixture}.txt").read, now: NOW)
    server.inventory_snapshots.create!(category: "scheduled_tasks", status: status, message: message, data: data, collected_at: NOW, checked_at: NOW)
  end

  test "the server tab lists the timers (problems first), the cron lines in words and the periodic scripts" do
    collect(servers(:web))
    sign_in users(:viewer)

    get server_path(servers(:web), tab: "schedules")

    assert_select "nav.server-tabs a[data-tab=schedules][aria-current=page]", text: /Tâches planifiées\s*15/
    assert_select "#server-scheduled-tasks" do
      assert_select ".scheduled-tasks-summary", text: /5 timers systemd\s+· 1 en échec\s+· 1 en retard\s+· 10 lignes cron · 5 scripts périodiques/
      assert_select "tr.systemd-timer:first-child[data-name='certbot.timer'] .timer-state", text: "en échec"
      assert_select "tr.systemd-timer:nth-child(2)[data-name='backup.timer'] .timer-state", text: "en retard"
      assert_select "tr.systemd-timer[data-name='certbot.timer']", text: /tous les jours à 0 h 00 et 12 h 00/
      assert_select "tr.systemd-timer[data-name='fstrim.timer'] .timer-state", text: "inactif"
      assert_select "tr.cron-task", 10
      assert_select "tr.cron-task", text: %r{tous les jours à 2 h 15\s+postgres\s+/usr/local/bin/backup.sh --all}
      assert_select "tr.cron-task", text: /toutes les 5 minutes\s+root/
      assert_select ".periodic-scripts li", text: /Tous les jours\s+\(\/etc\/cron.daily\) : apt-compat, dpkg, logrotate, man-db/
    end
  end

  test "operators can open the output of the timers that ran (the journal of their service, lazily)" do
    collect(servers(:web))
    sign_in users(:operator)
    get server_path(servers(:web), tab: "schedules")

    assert_select "tr.systemd-timer[data-name='backup.timer'] details.timer-journal" do
      assert_select "summary[title*='backup.service']", "Sortie"
      assert_select "turbo-frame[loading=lazy][src=?]", server_unit_journal_path(servers(:web), unit: "backup.service")
    end

    sign_in users(:viewer)
    get server_path(servers(:web), tab: "schedules")
    assert_select "details.timer-journal", 0
  end

  test "the tab explains a partial collection and an inventory not done yet" do
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "schedules")
    assert_select ".scheduled-tasks-empty", "Pas encore d'inventaire des tâches planifiées."

    collect(servers(:web), fixture: :no_root, status: "partial", message: "Crontabs des utilisateurs illisibles : Elio a besoin de root (sudo sans mot de passe).")
    get server_path(servers(:web), tab: "schedules")
    assert_select ".crontabs-unreadable", /Elio a besoin de root/
  end

  test "the fleet page finds which servers run a command, problems first" do
    collect(servers(:web))
    collect(servers(:db), fixture: :no_root)
    sign_in users(:viewer)

    get scheduled_tasks_path
    assert_response :success
    assert_select "nav.main-nav a[aria-current=page][href=?]", scheduled_tasks_path
    assert_select "#scheduled-tasks tr.scheduled-task:first-child", text: /certbot/
    assert_select "#scheduled-tasks tr.scheduled-task:first-child a[href=?]", server_path(servers(:web), tab: "schedules")

    get scheduled_tasks_path(q: "backup.sh")
    assert_select "tr.scheduled-task", 1
    assert_select "tr.scheduled-task", text: /#{servers(:web).name}.*cron.*backup\.sh/m

    get scheduled_tasks_path(q: "logrotate")
    assert_select "tr.scheduled-task", 3

    get scheduled_tasks_path(state: "late")
    assert_select "tr.scheduled-task", 1
    assert_select "tr.scheduled-task", text: /backup/

    get scheduled_tasks_path(q: "rien-de-tel")
    assert_select "p", text: "Aucune tâche planifiée ne correspond."
  end

  test "servers without this inventory are listed" do
    sign_in users(:viewer)
    get scheduled_tasks_path
    assert_select "p", text: /Sans inventaire des tâches planifiées/
  end
end
