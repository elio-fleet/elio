require "application_system_test_case"

class ServerFormTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup { sign_in users(:one) }

  test "testing the connection answers in the form and keeps what was typed" do
    stub_method_until_teardown(Ssh::Check, :call, Ssh::Check::Result.new(success: true, message: "ok", details: "deploy@10.0.0.9 a répondu"))
    visit new_server_path
    execute_script("window.noFullReload = true")

    fill_in "Nom", with: "Nouveau"
    fill_in "Hôte (IP ou nom de domaine)", with: "10.0.0.9"
    fill_in "Utilisateur", with: "deploy"
    click_on "Tester la connexion"

    assert_selector ".connection-test-result", text: "Elio peut se connecter à ce serveur."
    assert_field "Nom", with: "Nouveau"
    assert evaluate_script("window.noFullReload")
    assert_not Server.exists?(host: "10.0.0.9")
  end

  test "duplicating a server opens the form with its port and user" do
    visit server_path(servers(:db))
    find("#server-actions summary").click
    click_on "Dupliquer"

    assert_selector "h1", text: "Ajouter un serveur"
    assert_field "Port", with: servers(:db).port.to_s
    assert_field "Utilisateur", with: servers(:db).username
    assert_field "Nom", with: ""
  end
end
