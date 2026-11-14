require "test_helper"

# Controls the role cannot use are not shown.
class RoleBasedUiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup do
    keys = Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse([ ssh_keys(:main).public_key, Ssh::KeyGenerator.generate(comment: "bob").public_key ].join("\n")), error_title: nil, error_details: nil)
    stub_method_until_teardown(Keys::AuthorizedKeysReader, :call_all, keys_read(keys))
  end

  test "the navbar shows the role, and the settings to admins only" do
    { one: [ "Admin", 1 ], operator: [ "Opérateur", 0 ], viewer: [ "Lecture", 0 ] }.each do |role, (label, settings_links)|
      sign_in users(role)
      get root_path
      assert_select ".sidebar .user-role", label
      assert_select "nav a[title=Paramètres]", settings_links
    end
  end

  test "a viewer sees no management controls" do
    sign_in users(:viewer)

    get root_path
    assert_select "#onboarding", 0
    assert_select "form[action=?]", server_scans_path, 0

    get servers_path
    assert_select "a[href=?]", new_server_path, 0
    assert_select "a[title=Modifier]", 0
    assert_select "form[action=?]", server_scans_path, 0
    assert_select "button[title='Actualiser le statut']" # read-only checks stay available

    get server_path(servers(:web))
    assert_select "a[href=?]", edit_server_path(servers(:web)), 0
    assert_select "button.delete-server", 0

    get server_path(servers(:web), tab: "keys")
    assert_select ".add-key", 0

    get server_authorized_keys_path(servers(:web))
    assert_select "button[title='Supprimer la clé']", 0
    assert_select "a.add-to-keyring", 0
    assert_select "button.key-details-button", 2

    get public_keys_path
    assert_select "a[href=?]", new_public_key_path, 0
    assert_select "button[title=Supprimer]", 0

    get public_key_path(public_keys(:alice))
    assert_select "a[href=?]", edit_public_key_path(public_keys(:alice)), 0
    assert_select "#bulk-authorize", 0
  end

  test "an operator manages servers, keys and public_keys but not the settings" do
    servers(:web).update_columns(ssh_ok: true, inventoried_at: Time.current)
    sign_in users(:operator)

    get root_path
    assert_select "#onboarding", 0
    assert_select "form[action=?]", server_scans_path

    get servers_path
    assert_select "a[href=?]", new_server_path

    get server_path(servers(:web), tab: "keys")
    assert_select ".add-key button.add-key-button"

    get server_authorized_keys_path(servers(:web))
    assert_select "button[title='Supprimer la clé']", 1
    assert_select "a.add-to-keyring", 1

    get public_key_path(public_keys(:alice))
    assert_select "#bulk-authorize"
  end

  # Hidden, not greyed out: no link, lazy frame or quick-search entry leads a
  # viewer or an operator to a page that answers "forbidden".
  test "no link shown to a viewer or an operator leads to a forbidden page" do
    stub_method_until_teardown(Ssh::Check, :call, Ssh::Check::Result.new(success: true, message: "ok", details: "ok"))
    stub_method_until_teardown(Servers::Ping, :reachable?, true)
    %w[uptime_kuma ovh coolify technitium].each { |kind| Integration.create!(kind: kind).update_column(:enabled, true) }

    %i[viewer operator].each do |role|
      sign_in users(role)
      targets = crawled_pages.flat_map do |page|
        get page
        assert_response :success, "#{role}: #{page}"
        links_in(Nokogiri::HTML(response.body))
      end
      targets = targets.select { |href| href.start_with?("/") && !href.start_with?("//") }.map { |href| href.split("#").first }.uniq

      forbidden = targets.select { |href| get(href) && response.status == 403 }
      assert_empty forbidden, "#{role} is shown links to forbidden pages"
    end
  end

  test "the setup hint asks a non-admin to contact an administrator" do
    SshKey.delete_all
    stub_method_until_teardown(Ssh::Check, :call, Ssh::Check::Result.new(success: false, message: "Aucune clé SSH configurée", details: "x", reason: :missing_key))
    sign_in users(:operator)

    get server_ssh_check_path(servers(:web))

    assert_select ".ssh-setup-hint a[href=?]", settings_path, 0
    assert_select ".ssh-setup-hint", text: /Demandez à un administrateur/
  end

  private

  # The pages a non-admin reaches from the menu, every server tab and the extensions.
  def crawled_pages
    [ root_path, servers_path, server_groups_path, vulnerabilities_path, packages_path, ports_path, docker_path,
      scheduled_tasks_path, public_keys_path, public_key_path(public_keys(:alice)), activities_path, tasks_path, account_path,
      server_authorized_keys_path(servers(:web)), monitors_path, ovh_path, coolify_path, dns_records_path,
      *ServersController::TABS.map { |tab| server_path(servers(:web), tab: tab) } ]
  end

  # Links, lazy frames and quick-search entries of a page.
  def links_in(html)
    palette = html.at_css("script[data-command-palette-target=items]")
    [ *html.css("a[href]").map { |a| a["href"] }, *html.css("turbo-frame[src]").map { |frame| frame["src"] },
      *(palette ? JSON.parse(palette.text).map { |item| item["url"] } : []) ]
  end
end
