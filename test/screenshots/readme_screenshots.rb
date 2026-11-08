require "application_system_test_case"
require Rails.root.join("lib/elio/demo_fleet")

# Screenshots of the README and of the website (docs/screenshots/<language>), on a
# fictitious fleet (TEST-NET addresses 198.51.100.x, recorded command
# outputs of test/fixtures). Not part of the test suite (no _test suffix):
#
#   bin/rails tailwindcss:build
#   bin/rails test test/screenshots/readme_screenshots.rb
#
# Then optimize them: script/optimize-screenshots.
class ReadmeScreenshots < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include PackageHelpers
  include UptimeKumaHelpers
  include OvhHelpers

  FIX = Rails.root.join("test/fixtures/files/inventory")
  OUT = Rails.root.join("docs/screenshots")
  AGO = 9.minutes

  def fleet = @fleet ||= Elio::DemoFleet.new

  test "README and website screenshots" do
    stub_method_until_teardown(Servers::Ping, :reachable?, ->(host, *, **) { !host.end_with?(".77") })
    stub_method_until_teardown(Ssh::Check, :call, ->(*, **) { Ssh::Check::Result.new(success: true, message: "Connexion SSH réussie", details: "ok") })
    keys = [ public_keys(:alice).content, public_keys(:ci).content, ssh_keys(:main).public_key, Ssh::KeyGenerator.generate(comment: "jdupont@old-laptop").public_key ]
    # Elio logs in as root on "backup": the keys of its other accounts are read too.
    stub_method_until_teardown(Keys::AuthorizedKeysReader, :call_all, keys_read(lambda { |*, **|
      Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(keys.join("\n")), error_title: nil, error_details: nil)
    }, others: { "backup" => [ public_keys(:ci).content ] }))
    Server.delete_all
    built = fleet.build_core
    web, db, backup = built.values_at(:web, :db, :backup)

    # Extensions, synchronized for real against fake services (as in the tests).
    enable_uptime_kuma
    uptime_kuma_metrics(metrics_page(
      { id: 1, name: "[SRV] db-prod", hostname: "198.51.100.20", status: 1, uptime: 0.9998 },
      { id: 2, name: "[SRV] web-prod-1", hostname: "198.51.100.10", status: 1, uptime: 0.9991 },
      { id: 3, name: "shop.example.com", type: "http", url: "https://shop.example.com", hostname: "null", status: 1, cert_days: 23, uptime: 0.9995 },
      { id: 4, name: "[SRV] staging", hostname: "198.51.100.77", status: 0, uptime: 0.912 },
      { id: 5, name: "[SRV] db-prod PostgreSQL", type: "port", hostname: "198.51.100.20", status: 1, uptime: 1.0 },
      { id: 6, name: "Old VPN gateway", hostname: "192.0.2.44", status: 0, uptime: 0.0 }
    ))
    Integration.find_by!(kind: "uptime_kuma").sync!
    UptimeKumaMonitor.find_by!(monitor_id: "3").update!(server: web, matched_by: "manual")
    enable_ovh
    fake_ovh(JSON.parse(ovh_account(expiration: 12.days.from_now.to_date).to_json
                          .gsub("198.51.100.20", "198.51.100.11").gsub("203.0.113.10", "198.51.100.20").gsub("web.example.com.", "db-prod.example.internal.")
                          .gsub("198.51.100.7", "198.51.100.40")))
    Integration.find_by!(kind: "ovh").sync!
    fleet.build_dns_and_firewall(db)

    fleet.build_notes(db, admin: users(:one), operator: users(:operator))
    Server.find_each(&:refresh_health!)
    Activity.record!(:vulnerability_found, server: db, user: nil, count: 2, cves: %w[CVE-2024-45491 CVE-2024-45492], packages: %w[expat], image: "nginx:1.27")
    Activity.record!(:port_opened, server: db, user: nil, port: "6432/tcp", process: "docker-proxy")
    Activity.record!(:key_added, server: web, public_key: public_keys(:alice), unix_user: "deploy", user: users(:one), duration_label: "4 h")
    AccountSnapshot.record!(backup, AuthorizedKeysAccount.login(backup), AuthorizedKey.parse(keys.join("\n")))
    Automation.all_kinds.each do |automation|
      automation.update!(enabled: automation.inventory? || automation.kind.in?(%w[servers_ping vulnerabilities_update cve_scores_update docker_image_updates]),
                         last_run_at: 7.minutes.ago)
    end

    # One set per language (docs/screenshots/<language>/), the user's
    # language deciding over the browser's.
    access = Activity.of_kind(:key_added).last
    %w[en fr].each do |locale|
      I18n.with_locale(locale) do
        Automation.update_all(last_result: I18n.t("automation.results.inventoried", done: 7, count: 7))
        access.update!(data: access.data.merge("duration_label" => TemporaryAccess.label_for(4.hours)))
      end
      users(:one).update!(locale: locale)
      sign_in users(:one)
      @out = OUT.join(locale)
      FileUtils.mkdir_p(@out)
      shoot = lambda do |name, path, theme: "light", &before|
        visit root_path
        page.execute_script("localStorage.setItem('elio-theme', '#{theme}')")
        visit path
        before&.call
        sleep 1.2
        # As tall as the content (720 to 1400 px), not a fixed square with empty
        # space below: the bottom of the last element of <main>, plus the window
        # chrome (resize_to sets the outer size).
        content = evaluate_script(<<~JS).to_i
          Math.ceil(Math.max(...Array.from(document.querySelectorAll("main *")).map((e) => e.getBoundingClientRect().bottom + window.scrollY)) + 32)
        JS
        chrome = evaluate_script("window.outerHeight - window.innerHeight").to_i
        page.driver.browser.manage.window.resize_to(1400, content.clamp(720, 1400) + chrome)
        sleep 0.3
        page.save_screenshot(@out.join("#{name}.png").to_s)
        page.driver.browser.manage.window.resize_to(1400, 1400)
      end

      shoot.("overview", root_path)
      shoot.("fleet", servers_path(view: "list"))
      shoot.("fleet-grid", servers_path(view: "grid"))
      shoot.("fleet-dark", servers_path(view: "list"), theme: "dark")
      shoot.("server", server_path(db))
      shoot.("server-dark", server_path(db), theme: "dark")
      shoot.("vulnerabilities-by-package", server_path(db, tab: "vulnerabilities", view: "packages")) do
        find("li.vulnerability-package[data-package=linux] summary").click
      end
      shoot.("vulnerability-detail", server_path(db, tab: "vulnerabilities", view: "cves")) do
        find("tr.server-vulnerability[data-cve='CVE-2024-6387']").click
        assert_selector "dialog.vulnerability-dialog[open] .vulnerability-detail"
      end
      shoot.("fleet-vulnerabilities", vulnerabilities_path(view: "packages"))
      shoot.("docker", server_path(db, tab: "docker"))
      shoot.("scheduled-tasks", server_path(db, tab: "schedules"))
      shoot.("ports", server_path(db, tab: "firewall"))
      shoot.("firewall", server_path(db, tab: "firewall"))
      shoot.("firewall-settings", settings_firewall_path)
      shoot.("gandi", edit_settings_integration_path("gandi"))
      shoot.("ssh-keys", server_path(backup, tab: "keys"))
      shoot.("packages", packages_path(q: "ssl"))
      shoot.("score-providers", settings_vulnerabilities_path) { find("#score-providers").scroll_to(:top) }
      shoot.("automations", settings_automations_path)
      shoot.("uptime-kuma-monitors", monitors_path)
      shoot.("ovh", server_path(db)) { find("#server-hosting").scroll_to(:top) }
      shoot.("dns", dns_records_path)
      shoot.("notes", server_path(db, tab: "journal"))
      shoot.("docker-cves", docker_path(tab: "cves")) { first("section.image-vulnerabilities details summary").click }
      shoot.("keyring-outside", public_keys_path(kind: "outside"))
    end
  end
end
