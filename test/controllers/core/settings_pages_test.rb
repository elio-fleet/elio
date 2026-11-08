require "test_helper"

class SettingsPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  test "every settings page requires authentication" do
    [ settings_path, settings_notifications_path, settings_automations_path ].each do |path|
      get path
      assert_redirected_to new_user_session_path
    end
  end

  test "settings pages share tabs, the current one highlighted" do
    sign_in users(:one)

    { settings_path => "Général", settings_notifications_path => "Notifications", settings_users_path => "Utilisateurs", settings_automations_path => "Automatisations",
      settings_vulnerabilities_path => "Vulnérabilités", settings_docker_path => "Docker", settings_firewall_path => "Firewall", settings_integrations_path => "Extensions" }.each do |path, label|
      get path
      assert_select "nav.settings-nav a", 8
      assert_select "nav.settings-nav a[aria-current=page]", label
      assert_select "nav.main-nav a[aria-current=page]", "Paramètres"
    end
  end

  test "the automations are a page of the settings, not an entry of the sidebar" do
    sign_in users(:one)
    get settings_automations_path
    assert_select "nav.settings-nav a[aria-current=page]", "Automatisations"
    assert_select "nav.main-nav a[href=?]", settings_automations_path, 0
    assert_select "nav.main-nav a[aria-current=page]", "Paramètres"
  end

  test "the general settings keep the SSH key" do
    sign_in users(:one)
    get settings_path
    assert_select "#ssh-key-fingerprint", ssh_keys(:main).fingerprint
  end

  test "the automations page lists the automations with their state" do
    Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }.update!(enabled: true, last_run_at: 1.hour.ago, last_result: "3/3 serveur(s) scanné(s)")
    sign_in users(:one)

    get settings_automations_path

    assert_select "form#automations-form[action=?][data-controller=dirty-form]", settings_automations_update_path
    assert_select "form#automations-form tr.automation", 10
    assert_select "form#automations-form .save-bar[hidden]"
    scan = Automation.find_by!(kind: "keys_scan")
    assert_select "##{ActionView::RecordIdentifier.dom_id(scan)}" do
      assert_select ".automation-state", "Activée"
      assert_select ".automation-result", "3/3 serveur(s) scanné(s)"
      assert_select "input[type=checkbox][name=?][checked]", "automations[#{scan.id}][enabled]"
      assert_select "select[name=?] option[selected][value='360']", "automations[#{scan.id}][interval_minutes]", text: "Toutes les 6 heures"
      assert_select "button[form=?]", ActionView::RecordIdentifier.dom_id(scan, :run), text: /Lancer maintenant/
    end
    assert_select "form##{ActionView::RecordIdentifier.dom_id(scan, :run)}[action=?]", run_settings_automation_path(scan)
    assert_select "##{ActionView::RecordIdentifier.dom_id(Automation.find_by!(kind: "servers_ping"))} .automation-state", "Désactivée"
  end

  test "one Save for every automation" do
    scan = Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }
    ping = Automation.all_kinds.find { |automation| automation.kind == "servers_ping" }
    sign_in users(:one)

    patch settings_automations_update_path, params: { automations: { scan.id => { enabled: "1", interval_minutes: "60", server_group_ids: [ "", server_groups(:production).id.to_s ] },
                                                                     ping.id => { enabled: "0", interval_minutes: "15" } } }
    assert_redirected_to settings_automations_path
    assert_equal "Automatisations enregistrées.", flash[:notice]
    assert_equal [ true, 60, [ server_groups(:production).id ] ], [ scan.reload.enabled?, scan.interval_minutes, scan.server_group_ids ]
    assert_not ping.reload.enabled?

    patch settings_automations_update_path, params: { automations: { scan.id => { enabled: "1", interval_minutes: "7" } } }
    assert_predicate flash[:alert], :present?
    assert_equal 60, scan.reload.interval_minutes
  end

  test "enabling an automation and choosing its frequency" do
    scan = Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }
    sign_in users(:one)

    patch settings_automation_path(scan), params: { automation: { enabled: "1", interval_minutes: "60" } }

    assert_redirected_to settings_automations_path
    assert_equal "« Scan des clés » activée (toutes les heures, tout le parc).", flash[:notice]
    assert scan.reload.enabled?
    assert_equal 60, scan.interval_minutes
  end

  test "disabling an automation" do
    scan = Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }
    scan.update!(enabled: true)
    sign_in users(:one)

    patch settings_automation_path(scan), params: { automation: { enabled: "0", interval_minutes: "360" } }

    assert_not scan.reload.enabled?
    assert_equal "« Scan des clés » désactivée.", flash[:notice]
  end

  test "rejects a frequency that is not offered" do
    scan = Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }
    sign_in users(:one)

    patch settings_automation_path(scan), params: { automation: { enabled: "1", interval_minutes: "7" } }

    assert_redirected_to settings_automations_path
    assert flash[:alert].present?
    assert_equal 360, scan.reload.interval_minutes
  end

  test "running an automation now enqueues it as a task, even a quiet one" do
    %w[keys_scan health_check].each do |kind|
      automation = Automation.all_kinds.find { |candidate| candidate.kind == kind }
      sign_in users(:one)

      assert_difference -> { BackgroundTask.count } do
        post run_settings_automation_path(automation)
      end

      task = BackgroundTask.recent.first
      assert_equal [ "automation", automation, users(:one), "queued" ], [ task.kind, task.automation, task.user, task.status ]
      assert_enqueued_with(job: RunAutomationJob, args: [ automation, task ])
      assert_redirected_to task_path(task)
    end
  end

  test "an automation can be limited to some groups" do
    automation = Automation.all_kinds.find { |candidate| candidate.kind == "inventory_packages" }
    sign_in users(:one)

    get settings_automations_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(automation)}" do
      assert_select ".automation-scope", "Tout le parc"
      assert_select "details.automation-groups input[type=checkbox][name=?]", "automations[#{automation.id}][server_group_ids][]", 2
    end

    patch settings_automation_path(automation), params: { automation: { enabled: "1", interval_minutes: "5", server_group_ids: [ "", server_groups(:production).id.to_s ] } }

    assert_equal "« Inventaire des paquets » activée (toutes les 5 minutes, production).", flash[:notice]
    assert_equal [ server_groups(:production).id ], automation.reload.server_group_ids

    patch settings_automation_path(automation), params: { automation: { enabled: "1", interval_minutes: "5", server_group_ids: [ "" ] } }
    assert_equal [], automation.reload.server_group_ids
  end
end
