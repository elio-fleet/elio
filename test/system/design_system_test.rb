require "application_system_test_case"

# The rules of the design system (app/views/CLAUDE.md), checked on every main
# page: one title, one primary action at most, and no sideways scroll on a
# laptop (1024 px) or a desktop (1280 px) screen.
class DesignSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include PortHelpers

  setup do
    sign_in users(:one)
    record_ports(servers(:web))
    connection = Integration.create!(kind: "coolify", enabled: true).connections.create!(settings: { "url" => "https://coolify.example.com" }, secrets: { "token" => "t" })
    CoolifyResource.create!(connection: connection, kind: "server", uuid: "s1", name: "web", server: servers(:web), data: { "reachable" => true, "usable" => true })
    CoolifyResource.create!(connection: connection, kind: "application", uuid: "a1", name: "a-rather-long-application-name", status: "running:healthy", server: servers(:web),
                            data: { "domains" => %w[a-long-domain-name.example.com another-long-domain.example.com third.example.com], "git_branch" => "main", "git_commit" => "623a4be",
                                    "project" => "A long project name", "environment" => "production" })
  end

  teardown { page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride") }

  def pages
    web = servers(:web)
    [ root_path, servers_path, servers_path(view: "grid"), new_server_path, edit_server_path(web), server_groups_path, new_server_import_path,
      *ServersController::TABS.map { |tab| server_path(web, tab: tab) },
      vulnerabilities_path, packages_path, docker_path, docker_path(tab: "cves"), ports_path, scheduled_tasks_path,
      public_keys_path, new_public_key_path, public_key_path(public_keys(:alice)), activities_path, tasks_path,
      settings_path, settings_users_path, settings_notifications_path, settings_automations_path, settings_vulnerabilities_path,
      settings_docker_path, settings_firewall_path, settings_integrations_path, edit_settings_integration_path("coolify"),
      new_settings_integration_connection_path("coolify"), coolify_path, server_path(web, tab: "coolify"), account_path ]
  end

  [ 1024, 1280 ].each do |width|
    test "at #{width} px: one title, one primary action at most, no sideways scroll" do
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: width, height: 900, deviceScaleFactor: 1, mobile: false)
      pages.each do |path|
        visit path
        assert_selector "h1", count: 1
        primary = evaluate_script("[...document.querySelectorAll('main .btn-primary')].filter((e) => e.offsetParent && !e.closest('[hidden], dialog, .save-bar')).length")
        assert_operator primary, :<=, 1, "#{path} shows #{primary} primary buttons"
        overflow = evaluate_script("document.documentElement.scrollWidth - document.documentElement.clientWidth")
        assert_operator overflow, :<=, 0, "#{path} scrolls sideways by #{overflow} px at #{width} px"
      end
    end
  end
end
