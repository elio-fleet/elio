require "test_helper"

class AutomationJobsTest < ActiveJob::TestCase
  include StubHelpers

  test "RunAutomationJob runs the automation" do
    automation = Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }
    ran = []
    automation.define_singleton_method(:run!) { |task: nil| ran << [ kind, task ] }

    RunAutomationJob.perform_now(automation)

    assert_equal [ [ "keys_scan", nil ] ], ran
  end

  test "RunAutomationJob follows its task, one item per server" do
    automation = Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }
    task = automation.enqueue!(user: users(:one))
    scans = { "Web" => Keys::ServerScan::Result.new(error_title: nil), "Database" => Keys::ServerScan::Result.new(error_title: "Clé refusée") }

    stub_method(Keys::ServerScan, :call, ->(server, **) { scans.fetch(server.name, Keys::ServerScan::Result.new(error_title: nil)) }) do
      RunAutomationJob.perform_now(automation, task)
    end

    task.reload
    assert_equal "partial", task.status
    assert_match "serveurs scannés", task.result
    assert_equal Server.count, task.items.count
    failed = task.items.find_by!(server_name: "Database")
    assert_equal [ "failed", "Clé refusée" ], [ failed.status, failed.message ]
    assert task.started_at && task.finished_at
  end

  test "RunAutomationJob marks its task failed when the run crashes" do
    automation = Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }
    task = automation.enqueue!(user: users(:one))
    automation.define_singleton_method(:run!) { |task: nil| raise "boom" }

    assert_raises(RuntimeError) { RunAutomationJob.perform_now(automation, task) }

    assert_equal [ "failed", "Erreur interne (RuntimeError)" ], [ task.reload.status, task.result ]
  end

  test "RunDueAutomationsJob starts only the enabled automations that are due" do
    automations = Automation.all_kinds.index_by(&:kind)
    automations.each_value { |automation| automation.update!(enabled: false) }
    scan, ping = automations.values_at("keys_scan", "servers_ping")
    scan.update!(enabled: true, interval_minutes: 60, last_run_at: 2.hours.ago)
    ping.update!(enabled: true, interval_minutes: 15, last_run_at: 5.minutes.ago)

    freeze_time do
      RunDueAutomationsJob.perform_now

      assert_enqueued_jobs 1, only: RunAutomationJob
      task = BackgroundTask.sole
      assert_equal [ "automation", scan, nil, "Scan des clés" ], [ task.kind, task.automation, task.user, task.label ]
      assert_enqueued_with(job: RunAutomationJob, args: [ scan, task ])
      assert_equal Time.current, scan.reload.last_run_at
    end
  end

  test "RunDueAutomationsJob ignores disabled automations" do
    Automation.all_kinds.each { |automation| automation.update!(enabled: false) }

    RunDueAutomationsJob.perform_now

    assert_no_enqueued_jobs only: RunAutomationJob
  end

  test "on a new installation, the first tick creates the automations and starts the health check, the vulnerability feeds and the image checks" do
    RunDueAutomationsJob.perform_now

    assert_equal 13, Automation.count
    assert_enqueued_with(job: RunAutomationJob, args: [ Automation.find_by!(kind: "health_check"), nil ])
    assert_enqueued_jobs 4, only: RunAutomationJob
    assert_equal [ "Mise à jour des vulnérabilités", "Notes de gravité des CVE", "Mises à jour des images Docker" ], BackgroundTask.order(:id).pluck(:label), "the quiet health check is not listed in the tasks"
  end

  test "due automations are checked every minute in development and production" do
    recurring = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[development production].each do |environment|
      assert_equal({ "class" => "RunDueAutomationsJob", "schedule" => "every minute" }, recurring.dig(environment, "run_due_automations"))
    end
  end
end
