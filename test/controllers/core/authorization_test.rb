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
    stub_method_until_teardown(Ssh::Diagnosis, :call, Ssh::Diagnosis::Result.new(steps: []))
    stub_method_until_teardown(Servers::Ping, :reachable?, true)
    stub_method_until_teardown(Keys::AccessGrant, :call, Keys::PublicKeyAuthorization::Result.new(status: :added, error_title: nil, error_details: nil))
    stub_method_until_teardown(Keys::Revocation, :call, Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil))
    stub_method_until_teardown(Notifications::Slack, :post, nil)
  end


  # The demo extension with several connections, registered for one request; yields a connection.
  def with_demo_multi
    previous = Integration.registry
    Integration.registry = previous.merge("demo_multi" => "DemoMultiIntegration")
    integration = Integration.find_or_create_by!(kind: "demo_multi")
    connection = integration.connections.first || integration.connections.create!(settings: { "url" => "https://a.example" }, secrets: { "token" => "t" })
    yield connection
  ensure
    Integration.registry = previous
  end

  REQUESTS = {
    view: {
      "dashboard" => -> { get root_path },
      "own language" => -> { patch locale_account_path, params: { user: { locale: "en" } } },
      "servers index" => -> { get servers_path },
      "export the fleet list" => -> { get servers_path(format: :csv) },
      "choose the fleet columns" => -> { patch server_columns_path, params: { columns: %w[disk] } },
      "export the fleet list" => -> { get servers_path(format: :csv) },
      "choose the fleet columns" => -> { patch server_columns_path, params: { columns: %w[disk] } },
      "server page" => -> { get server_path(servers(:web)) },
      "server port check" => -> { get server_ping_path(servers(:web)) },
      "server SSH check" => -> { get server_ssh_check_path(servers(:web)) },
      "server SSH diagnosis" => -> { get server_ssh_diagnosis_path(servers(:web)) },
      "server keys" => -> { get server_authorized_keys_path(servers(:web)) },
      "server temporary accesses" => -> { get server_temporary_accesses_path(servers(:web)) },
      "server packages" => -> { get server_packages_path(servers(:web)) },
      "server commands" => -> { get server_commands_path(servers(:web)) },
      "fleet packages" => -> { get packages_path(q: "ssl") },
      "fleet ports" => -> { get ports_path },
      "fleet scheduled tasks" => -> { get scheduled_tasks_path },
      "fleet vulnerabilities" => -> { get vulnerabilities_path },
      "export the fleet vulnerabilities" => -> { get vulnerabilities_path(format: :csv) },
      "fleet docker" => -> { get docker_path },
      "vulnerability detail" => -> { Vulnerability.create!(source: "debian", release: "bookworm", package: "x", cve: "CVE-2024-1", severity: "low") && get(vulnerability_path("CVE-2024-1")) },
      "server docker" => -> { get server_path(servers(:web), tab: "docker") },
      "server vulnerabilities" => -> { get server_path(servers(:web), tab: "vulnerabilities") },
      "server notes" => -> { get server_path(servers(:web), tab: "journal") },
      "add a note" => -> { post server_notes_path(servers(:web)), params: { server_note: { body: "Hello" } } },
      "preview a note" => -> { post preview_server_notes_path(servers(:web)), params: { server_note: { body: "**x**" } } },
      "ping one server" => -> { post server_ping_path(servers(:web)) },
      "ping all servers" => -> { post server_pings_path },
      "public_keys index" => -> { get public_keys_path },
      "server groups" => -> { get server_groups_path },
      "public_key page" => -> { get public_key_path(public_keys(:alice)) },
      "activities" => -> { get activities_path },
      "export the journal" => -> { get activities_path(format: :csv) },
      "one event" => -> { get activity_path(Activity.record!(:server_created, server: servers(:web))) },
      "tasks" => -> { get tasks_path },
      "ovh" => -> { Integration.create!(kind: "ovh", enabled: true, settings: { "application_key" => "a" }, secrets: { "application_secret" => "s", "consumer_key" => "c" }) && get(ovh_path) },
      "coolify" => -> { Integration.create!(kind: "coolify", enabled: true) && get(coolify_path) },
      "monitors" => -> { Integration.create!(kind: "uptime_kuma", enabled: true, settings: { "url" => "https://u.test" }, secrets: { "api_key" => "k" }) && get(monitors_path) },
      "dns records" => -> { Integration.create!(kind: "technitium", enabled: true, settings: { "url" => "https://d.test" }, secrets: { "api_token" => "t" }) && get(dns_records_path) },
      "task page" => -> { get task_path(BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: [], user: nil)) },
      "own account" => -> { get account_path },
      "set up 2FA" => -> { get new_two_factor_path }
    },
    operate: {
      "journal of a failed unit" => -> { get server_unit_journal_path(servers(:web), unit: "nginx.service") },
      "attach a DNS name" => -> {
        Integration.create!(kind: "technitium", enabled: true, settings: { "url" => "https://d.test" }, secrets: { "api_token" => "t" })
        post dns_record_link_path(DnsRecord.create!(source: "technitium", source_id: "x.a.test", zone: "a.test", name: "x.a.test", record_type: "A", value: "203.0.113.1")), params: { server_id: servers(:web).id }
      },
      "attach several DNS names" => -> {
        Integration.create!(kind: "technitium", enabled: true, settings: { "url" => "https://d.test" }, secrets: { "api_token" => "t" })
        record = DnsRecord.create!(source: "technitium", source_id: "y.a.test", zone: "a.test", name: "y.a.test", record_type: "A", value: "203.0.113.2")
        post dns_link_batch_path, params: { record_ids: [ record.id.to_s ], server_id: servers(:web).id }
      },
      "new server" => -> { get new_server_path },
      "create server" => -> { post servers_path, params: { server: { name: "New", host: "10.0.0.1", port: 22, username: "root" } } },
      "duplicate server" => -> { get new_server_path(from: servers(:web).id) },
      "test a server connection" => -> { post test_connection_servers_path, params: { server: { host: "10.0.0.1", port: 22, username: "root" } }, as: :turbo_stream },
      "edit server" => -> { get edit_server_path(servers(:web)) },
      "update server" => -> { patch server_path(servers(:web)), params: { server: { name: "Renamed" } } },
      "delete server" => -> { delete server_path(servers(:web)) },
      "ignore an unexpected port" => -> { post server_expected_port_path(servers(:web)), params: { port: 8081, proto: "tcp" } },
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
      "rerun an inventory" => -> { post task_rerun_path(BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: [ servers(:web) ]).tap { |task| task.items.each { |item| item.finish!(:failed) } }) },
      "authorize a public_key" => -> { post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id } },
      "remove a key" => -> { delete server_authorized_key_path(servers(:web)), params: { key: "AAAA" } },
      "new public_key" => -> { get new_public_key_path },
      "create public_key" => -> { post public_keys_path, params: { public_key: { name: "New", content: Ssh::KeyGenerator.generate.public_key } } },
      "edit public_key" => -> { get edit_public_key_path(public_keys(:alice)) },
      "update public_key" => -> { patch public_key_path(public_keys(:alice)), params: { public_key: { name: "Renamed" } } },
      "delete public_key" => -> { delete public_key_path(public_keys(:alice)) },
      "grant a public_key on servers" => -> { post public_key_accesses_path(public_keys(:alice)), params: { server_ids: [ servers(:web).id ] } },
      "revoke a public_key access" => -> { delete public_key_access_path(public_keys(:alice)), params: { server_id: servers(:web).id } },
      "claim a keyring key as mine" => -> { post account_keys_path, params: { public_key_id: public_keys(:alice).id } },
      "release one of my keys" => -> { delete account_key_path(public_keys(:alice)) },
      "add my key to a server" => -> { post server_my_key_accesses_path(servers(:web)) },
      "remove my key from a server" => -> { delete server_my_key_access_path(servers(:web), 0) },
      "extend a temporary access" => -> { patch server_temporary_access_path(servers(:web), 0), params: { duration: "60" } }
    },
    administer: {
      "DNS alerts" => -> { patch settings_dns_alerts_path, params: { dns_alerts: { outside: "1" } } },
      "general settings" => -> { get settings_path },
      "save the general settings" => -> { patch settings_path, params: { app_setting: { default_locale: "fr" } } },
      "save the automations" => -> { patch settings_automations_update_path, params: { automations: {} } },
      "generate the Elio key" => -> { post ssh_key_path },
      "trust a new host key" => -> { post server_host_key_path(servers(:web)), params: { fingerprint: "SHA256:new" } },
      "changed host keys" => -> { get host_key_batch_path },
      "trust several new host keys" => -> { post host_key_batch_path },
      "notifications" => -> { get settings_notifications_path },
      "new channel" => -> { get new_settings_notification_channel_path },
      "create channel" => -> { post settings_notification_channels_path, params: { notification_channel: { name: "#x", webhook_url: WEBHOOK, activity_kinds: [ "" ] } } },
      "edit channel" => -> { get edit_settings_notification_channel_path(create_channel) },
      "test channel" => -> { post test_settings_notification_channel_path(create_channel) },
      "delete channel" => -> { delete settings_notification_channel_path(create_channel) },
      "automations" => -> { get settings_automations_path },
      "extensions" => -> { get settings_integrations_path },
      "new extension connection" => -> { with_demo_multi { get new_settings_integration_connection_path("demo_multi") } },
      "add an extension connection" => -> { with_demo_multi { post settings_integration_connections_path("demo_multi"), params: { connection: { values: { url: "https://a.example", token: "t" } } } } },
      "test an extension connection" => -> { with_demo_multi { post test_settings_integration_connections_path("demo_multi"), params: { connection: { values: { url: "https://a.example" } } } } },
      "edit an extension connection" => -> { with_demo_multi { |connection| get edit_settings_integration_connection_path("demo_multi", connection) } },
      "update an extension connection" => -> { with_demo_multi { |connection| patch settings_integration_connection_path("demo_multi", connection), params: { connection: { name: "x" } } } },
      "delete an extension connection" => -> { with_demo_multi { |connection| delete settings_integration_connection_path("demo_multi", connection) } },
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
      "resend an invitation" => -> { post resend_settings_invitation_path(Invitation.create!(email: "y@example.com", invited_by: users(:one)).tap { |invitation| invitation.update_columns(expires_at: 1.day.ago) }) },
      "revoke an invitation" => -> { delete settings_invitation_path(Invitation.create!(email: "x@example.com", invited_by: users(:one))) },
      "change a user's role" => -> { patch settings_user_path(users(:viewer)), params: { user: { role: "operator", public_key_id: "" } } },
      "deactivate a user" => -> { post deactivate_settings_user_path(users(:viewer)) },
      "reactivate a user" => -> { post reactivate_settings_user_path(users(:viewer)) },
      "reset a user's 2FA" => -> { post reset_two_factor_settings_user_path(users(:viewer)) },
      "unlock a user" => -> { post unlock_settings_user_path(users(:viewer)) },
      "ask a user for a new password" => -> { post require_password_change_settings_user_path(users(:viewer)) },
      "start a key rotation" => -> { post settings_key_rotations_path },
      "follow a key rotation" => -> { get settings_key_rotation_path(KeyRotation.start!(by: users(:one))) },
      "retry a key rotation" => -> { post retry_settings_key_rotation_path(KeyRotation.start!(by: users(:one))) },
      "finalize a key rotation" => -> { post finalize_settings_key_rotation_path(KeyRotation.start!(by: users(:one))) },
      "resume a key rotation" => -> { post resume_settings_key_rotation_path(KeyRotation.start!(by: users(:one))) },
      "simulate a key rotation" => -> { post settings_key_rotation_check_path },
      "rerun a key rotation check" => -> { post task_rerun_path(BackgroundTask.enqueue!(kind: "key_rotation_check", label: "Simulation", servers: [ servers(:web) ]).tap { |task| task.items.each { |item| item.finish!(:failed) } }) },
      "require 2FA for admins" => -> { patch settings_security_path, params: { app_setting: { require_admin_two_factor: "0" } } },
      "health thresholds" => -> { patch settings_health_thresholds_path, params: { app_setting: { health_disk_warn: 80 } } },
      "prompt instructions" => -> { patch settings_prompt_instructions_path, params: { prompt_instructions: { firewall: "x" } } },
      "firewall settings" => -> { get settings_firewall_path },
      "firewall options" => -> { patch settings_firewall_options_path, params: { app_setting: { ufw_block_ipv6: "1" } } },
      "add an SSH source" => -> { post settings_ssh_sources_path, params: { ssh_source: { name: "Elio", cidr: "203.0.113.5" } } },
      "delete an SSH source" => -> { delete settings_ssh_source_path(SshSource.create!(name: "X#{SecureRandom.hex(3)}", cidr: "203.0.113.9")) },
      "move an SSH source" => -> { patch move_settings_ssh_source_path(SshSource.create!(name: "Y#{SecureRandom.hex(3)}", cidr: "203.0.113.8"), direction: "up") },
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
    assert_select "p.forbidden-message", text: "Votre rôle (Lecture) ne permet pas cette action : il faut le rôle Admin ou Opérateur."
    assert_select "a.forbidden-back[href=?]", root_path, text: "Retour à la vue d'ensemble"
  end

  test "a forbidden page names the role needed and leads back to the previous page" do
    sign_in users(:operator)
    get settings_path, headers: { "Referer" => "http://www.example.com#{server_path(servers(:web))}?tab=keys" }

    assert_select "p.forbidden-message", text: "Votre rôle (Opérateur) ne permet pas cette action : il faut le rôle Admin."
    assert_select "a.forbidden-back[href=?]", "#{server_path(servers(:web))}?tab=keys", text: "Retour à la page précédente"
    assert_select "a[href=?]", root_path, text: "Retour à la vue d'ensemble"
  end

  test "a forbidden page never leads back to another site" do
    sign_in users(:viewer)
    get new_server_path, headers: { "Referer" => "https://evil.example/phish" }

    assert_select "a.forbidden-back[href=?]", root_path
    assert_select "a[href*=evil]", 0
  end

  test "a rule of its own (someone else's note) keeps the short message" do
    note = ServerNote.create!(server: servers(:web), user: users(:one), body: "Admin note")
    sign_in users(:operator)
    get edit_server_note_path(servers(:web), note)

    assert_response :forbidden
    assert_select "p.forbidden-message", text: "Votre rôle (Opérateur) ne permet pas cette action."
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
