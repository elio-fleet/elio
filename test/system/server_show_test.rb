require "application_system_test_case"

class ServerShowTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include TcpHelpers
  include StubHelpers
  include ActionView::RecordIdentifier

  setup do
    sign_in users(:one)
  end

  test "opening a server from the servers page" do
    visit servers_path
    click_on "Web"

    assert_selector "h1", text: "Web"
    assert_selector "#server-health .server-status"
  end

  test "the port and SSH access are checked on display and can be checked again" do
    visit server_path(servers(:web))
    execute_script("window.noFullReload = true")

    within("#server-health") do
      assert_selector ".server-status", text: "Injoignable"
      assert_selector ".ssh-check-result", text: "Connexion impossible"
      assert_selector ".ssh-check-details"
      assert_no_selector ".health-checking"

      find("a[title='Revérifier le port']").click
      assert_selector ".server-status", text: "Injoignable"
      find("a[title='Retester la connexion SSH']").click
      assert_selector ".ssh-check-result", text: "Connexion impossible"
    end
    assert evaluate_script("window.noFullReload")
    assert_selector "h1", text: "Web"
  end


  test "authorized keys load lazily in their tab and can be reloaded" do
    visit server_path(servers(:web))
    within("nav.server-tabs") { click_on "Clés SSH" }
    assert_selector "nav.server-tabs a[aria-current=page]", text: "Clés SSH"

    within("#server-authorized-keys") do
      assert_selector ".authorized-keys-error", text: "Connexion impossible"
      click_on "Recharger les clés"
      assert_selector ".authorized-keys-error", text: "Connexion impossible"
    end
    assert_selector "h1", text: "Web"
  end

  # Cancelling closes the dialog, but the browser fires its "close" event
  # later: a confirmation opened before that event must not take it for its
  # own answer (it did, and the deletion confirmed next did nothing).
  test "a confirmation opened right after a cancelled one still waits for its answer" do
    visit server_path(servers(:backup))
    dismiss_app_confirm { first("button.delete-server").click }

    page.execute_script(<<~JS)
      document.querySelector("button.delete-server").click()
      document.querySelector("#confirm-dialog button[value=cancel]").click()
      document.querySelector("button.delete-server").click()
    JS
    accept_app_confirm("Supprimer le serveur") { }

    assert_selector "h1", text: "Serveurs"
    assert_text "Le serveur « Backup » a été supprimé d'Elio."
  end

  test "deleting a server from its page" do
    visit server_path(servers(:backup))

    dismiss_app_confirm { first("button.delete-server").click }
    assert_selector "h1", text: "Backup"

    accept_app_confirm("Supprimer le serveur") { first("button.delete-server").click }

    assert_selector "h1", text: "Serveurs"
    assert_text "Le serveur « Backup » a été supprimé d'Elio."
    assert_no_selector "#servers", text: "Backup"

    visit activities_path
    assert_selector "li.activity", text: "Serveur « Backup » supprimé d'Elio"
  end

  test "opening and closing the details of a key" do
    stub_method_until_teardown(Keys::AuthorizedKeysReader, :call_all, keys_read(Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(public_keys(:alice).content), error_title: nil, error_details: nil)))
    visit server_path(servers(:web), tab: "keys")

    within("#server-authorized-keys") do
      assert_selector "li.authorized-key", text: "alice@laptop"
      assert_no_text public_keys(:alice).fingerprint
      find("button[title='Détails de la clé']").click
    end

    within("dialog.key-details[open]") do
      assert_text public_keys(:alice).fingerprint
      find("button[aria-label=Fermer]").click
    end
    assert_no_selector "dialog.key-details[open]"

    find("#server-authorized-keys button[title='Détails de la clé']").click
    find("dialog.key-details[open]").send_keys(:escape)
    assert_no_selector "dialog.key-details[open]"
  end
end
