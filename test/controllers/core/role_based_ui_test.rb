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

  test "the setup hint asks a non-admin to contact an administrator" do
    SshKey.delete_all
    stub_method_until_teardown(Ssh::Check, :call, Ssh::Check::Result.new(success: false, message: "Aucune clé SSH configurée", details: "x", reason: :missing_key))
    sign_in users(:operator)

    get server_ssh_check_path(servers(:web))

    assert_select ".ssh-setup-hint a[href=?]", settings_path, 0
    assert_select ".ssh-setup-hint", text: /Demandez à un administrateur/
  end
end
