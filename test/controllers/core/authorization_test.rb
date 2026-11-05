require "test_helper"

# Every action, for every role: allowed (any status but 403) or forbidden (403).
class AuthorizationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include SlackHelpers

  ROLES = %i[one operator viewer].freeze # admin, operator, viewer
  ALLOWED = { view: %i[one operator viewer], operate: %i[one operator], administer: %i[one] }.freeze

  setup do
    # Nothing may reach a real server or Slack.
    ok_keys = Keys::AuthorizedKeysReader::Result.new(keys: [], error_title: nil, error_details: nil)
    stub_method_until_teardown(Keys::AuthorizedKeysReader, :call_all, keys_read(ok_keys))
    stub_method_until_teardown(Ssh::Check, :call, Ssh::Check::Result.new(success: true, message: "ok", details: "ok"))
    stub_method_until_teardown(Servers::Ping, :reachable?, true)
    stub_method_until_teardown(Keys::AccessGrant, :call, Keys::PublicKeyAuthorization::Result.new(status: :added, error_title: nil, error_details: nil))
    stub_method_until_teardown(Keys::Revocation, :call, Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil))
    stub_method_until_teardown(Notifications::Slack, :post, nil)
  end


  REQUESTS = {
    view: {
      "dashboard" => -> { get root_path },
      "own language" => -> { patch locale_account_path, params: { user: { locale: "en" } } },
      "servers index" => -> { get servers_path },
      "server page" => -> { get server_path(servers(:web)) },
      "server port check" => -> { get server_ping_path(servers(:web)) },
      "server SSH check" => -> { get server_ssh_check_path(servers(:web)) },
      "server keys" => -> { get server_authorized_keys_path(servers(:web)) },
      "server packages" => -> { get server_packages_path(servers(:web)) },
      "fleet packages" => -> { get packages_path(q: "ssl") },
      "fleet ports" => -> { get ports_path },
      "fleet scheduled tasks" => -> { get scheduled_tasks_path },
      "fleet vulnerabilities" => -> { get vulnerabilities_path },
      "fleet docker" => -> { get docker_path },
      "vulnerability detail" => -> { Vulnerability.create!(source: "debian", release: "bookworm", package: "x", cve: "CVE-2024-1", severity: "low") && get(vulnerability_path("CVE-2024-1")) },
      "server docker" => -> { get server_path(servers(:web), tab: "docker") },
      "server vulnerabilities" => -> { get server_path(servers(:web), tab: "vulnerabilities") },
      "ping one server" => -> { post server_ping_path(servers(:web)) },
      "ping all servers" => -> { post server_pings_path },
      "public_keys index" => -> { get public_keys_path },
      "server groups" => -> { get server_groups_path },
      "public_key page" => -> { get public_key_path(public_keys(:alice)) },
      "activities" => -> { get activities_path },
      "tasks" => -> { get tasks_path },
      "ovh" => -> { Integration.create!(kind: "ovh", enabled: true, settings: { "application_key" => "a" }, secrets: { "application_secret" => "s", "consumer_key" => "c" }) && get(ovh_path) },
      "monitors" => -> { Integration.create!(kind: "uptime_kuma", enabled: true, settings: { "url" => "https://u.test" }, secrets: { "api_key" => "k" }) && get(monitors_path) },
      "task page" => -> { get task_path(BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: [], user: nil)) },
      "own account" => -> { get account_path },
      "set up 2FA" => -> { get new_two_factor_path }
    },
    operate: {
      "new server" => -> { get new_server_path },
      "create server" => -> { post servers_path, params: { server: { name: "New", host: "10.0.0.1", port: 22, username: "root" } } },
      "edit server" => -> { get edit_server_path(servers(:web)) },
      "update server" => -> { patch server_path(servers(:web)), params: { server: { name: "Renamed" } } },
      "delete server" => -> { delete server_path(servers(:web)) },
      "import servers form" => -> { get new_server_import_path },
      "preview a server import" => -> { post preview_server_import_path, params: { content: "a,10.0.0.1", import_format: "csv" } },
      "import servers" => -> { post server_import_path, params: { content: "a,10.0.0.1", import_format: "csv" } },
      "new server group" => -> { get new_server_group_path },
      "create server group" => -> { post server_groups_path, params: { server_group: { name: "New", color: "red" } } },
      "edit server group" => -> { get edit_server_group_path(server_groups(:production)) },
      "update server group" => -> { patch server_group_path(server_groups(:production)), params: { server_group: { name: "Renamed" } } },
      "delete server group" => -> { delete server_group_path(server_groups(:production)) },
      "scan keys" => -> { post server_scans_path },
      "inventory of a server" => -> { post server_inventory_path(servers(:web)) },
      "inventory of every server" => -> { post server_inventories_path },
      "authorize a public_key" => -> { post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id } },
      "remove a key" => -> { delete server_authorized_key_path(servers(:web)), params: { key: "AAAA" } },
      "new public_key" => -> { get new_public_key_path },
      "create public_key" => -> { post public_keys_path, params: { public_key: { name: "New", content: Ssh::KeyGenerator.generate.public_key } } },
      "edit public_key" => -> { get edit_public_key_path(public_keys(:alice)) },
      "update public_key" => -> { patch public_key_path(public_keys(:alice)), params: { public_key: { name: "Renamed" } } },
      "delete public_key" => -> { delete public_key_path(public_keys(:alice)) },
      "grant a public_key on servers" => -> { post public_key_accesses_path(public_keys(:alice)), params: { server_ids: [ servers(:web).id ] } },
      "revoke a public_key access" => -> { delete public_key_access_path(public_keys(:alice)), params: { server_id: servers(:web).id } }
    },
    administer: {
      "general settings" => -> { get settings_path },
      "generate the Elio key" => -> { post ssh_key_path },
      "trust a new host key" => -> { post server_host_key_path(servers(:web)), params: { fingerprint: "SHA256:new" } },
      "notifications" => -> { get settings_notifications_path },
      "new channel" => -> { get new_settings_notification_channel_path },
      "create channel" => -> { post settings_notification_channels_path, params: { notification_channel: { name: "#x", webhook_url: WEBHOOK, activity_kinds: [ "" ] } } },
      "edit channel" => -> { get edit_settings_notification_channel_path(create_channel) },
      "test channel" => -> { post test_settings_notification_channel_path(create_channel) },
      "delete channel" => -> { delete settings_notification_channel_path(create_channel) },
      "automations" => -> { get settings_automations_path },
      "extensions" => -> { get settings_integrations_path },
      "vulnerability feeds" => -> { get settings_vulnerabilities_path },
      "docker settings" => -> { get settings_docker_path },
      "update the CVE scores" => -> { post scores_settings_vulnerabilities_path },
      "new score provider" => -> { get new_settings_score_provider_path },
      "create score provider" => -> { post settings_score_providers_path, params: { score_provider: { name: "X", url_template: "https://x.test/{cve}", format: "json", json_path: "a" } } },
      "move score provider" => -> { patch move_settings_score_provider_path(ScoreProvider.all_providers.last, direction: "up") },
      "toggle score provider" => -> { patch toggle_settings_score_provider_path(ScoreProvider.all_providers.last) },
      "test score provider" => -> { post test_settings_score_provider_path(ScoreProvider.all_providers.last), params: { cve: "bad" } },
      "preview score provider" => -> { post preview_settings_score_providers_path, params: { score_provider: { name: "X", url_template: "bad", format: "json" } } },
      "docker alerts" => -> { patch settings_docker_path, params: { app_setting: { docker_alert_updates: "1" } } },
      "check the image registries" => -> { post check_settings_docker_path },
      "vulnerability alerts" => -> { patch settings_vulnerabilities_path, params: { app_setting: { vulnerability_alert_severity: "critical" } } },
      "update the vulnerability feeds" => -> { post refresh_settings_vulnerabilities_path },
      "import a vulnerability feed" => -> { post import_settings_vulnerabilities_path },
      "update automation" => -> { patch settings_automation_path(Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }), params: { automation: { enabled: "1", interval_minutes: "60" } } },
      "run automation" => -> { post run_settings_automation_path(Automation.all_kinds.find { |automation| automation.kind == "keys_scan" }) },
      "users" => -> { get settings_users_path },
      "invite a user" => -> { post settings_invitations_path, params: { invitation: { email: "new@example.com", role: "viewer" } } },
      "revoke an invitation" => -> { delete settings_invitation_path(Invitation.create!(email: "x@example.com", invited_by: users(:one))) },
      "change a user's role" => -> { patch settings_user_path(users(:viewer)), params: { user: { role: "operator", public_key_id: "" } } },
      "deactivate a user" => -> { post deactivate_settings_user_path(users(:viewer)) },
      "reactivate a user" => -> { post reactivate_settings_user_path(users(:viewer)) },
      "reset a user's 2FA" => -> { post reset_two_factor_settings_user_path(users(:viewer)) },
      "start a key rotation" => -> { post settings_key_rotations_path },
      "follow a key rotation" => -> { get settings_key_rotation_path(KeyRotation.start!(by: users(:one))) },
      "retry a key rotation" => -> { post retry_settings_key_rotation_path(KeyRotation.start!(by: users(:one))) },
      "finalize a key rotation" => -> { post finalize_settings_key_rotation_path(KeyRotation.start!(by: users(:one))) },
      "require 2FA for admins" => -> { patch settings_security_path, params: { app_setting: { require_admin_two_factor: "0" } } },
      "health thresholds" => -> { patch settings_health_thresholds_path, params: { app_setting: { health_disk_warn: 80 } } },
      "default language" => -> { patch settings_language_path, params: { app_setting: { default_locale: "en" } } }
    }
  }.freeze

  REQUESTS.each do |permission, requests|
    requests.each do |name, request|
      ROLES.each do |role|
        allowed = ALLOWED.fetch(permission).include?(role)

        test "#{role == :one ? "admin" : role} #{allowed ? "can" : "cannot"} #{name}" do
          sign_in users(role)
          instance_exec(&request)

          if allowed
            assert_not_equal 403, response.status, "#{name} should be allowed for #{role}"
            assert_operator response.status, :<, 500
          else
            assert_response :forbidden
          end
        end
      end
    end
  end

  test "signed out users are still sent to the sign in page" do
    get servers_path
    assert_redirected_to new_user_session_path
  end

  test "a forbidden page explains why" do
    sign_in users(:viewer)
    get new_server_path

    assert_select "h1", "Accès refusé"
    assert_select "p", text: "Votre rôle (Lecture) ne permet pas cette action."
  end

  test "a forbidden Turbo Stream request shows a toast" do
    sign_in users(:viewer)
    post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id }, as: :turbo_stream

    assert_turbo_stream action: :update, target: "flash", status: :forbidden do
      assert_select ".toast-alert", text: /Votre rôle \(Lecture\) ne permet pas cette action/
    end
  end

  test "a forbidden Turbo Frame request answers inside the frame" do
    sign_in users(:viewer)
    get new_server_path, headers: { "Turbo-Frame" => "some_frame" }

    assert_response :forbidden
    assert_select "turbo-frame#some_frame p.forbidden"
  end

  test "nothing changes when an action is forbidden" do
    sign_in users(:viewer)

    assert_no_difference -> { Server.count } do
      delete server_path(servers(:web))
    end
    assert_no_difference -> { SshKey.count + Activity.count } do
      post ssh_key_path
    end
  end
end
