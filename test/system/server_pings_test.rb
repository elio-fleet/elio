require "application_system_test_case"

class ServerPingsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include TcpHelpers
  include ActionView::RecordIdentifier

  setup do
    sign_in users(:one)
    visit servers_path
    # Survives Turbo Stream updates, lost on a full page visit.
    execute_script("window.noFullReload = true")
  end

  test "refreshing one server updates its badge in place" do
    within "##{dom_id(servers(:web))}" do
      assert_selector ".server-status", text: "En ligne"
      click_on "Actualiser le statut"
      assert_selector ".server-status", text: "Injoignable"
    end

    assert_selector "#flash", text: "« Web » est injoignable."
    within("##{dom_id(servers(:backup))}") { assert_selector ".server-status", text: "Inconnu" }
    assert evaluate_script("window.noFullReload")
  end

  test "refreshing all servers updates every badge in place" do
    click_on "Actualiser les statuts"

    assert_selector "#flash", text: "Statuts actualisés : 0 en ligne, 3 injoignable(s)."
    assert_selector ".server-status", text: "Injoignable", count: 3
    assert_no_selector ".server-status", text: "Vérification…"
    assert evaluate_script("window.noFullReload")
  end

  test "edit icon opens the edit page" do
    within("##{dom_id(servers(:web))}") { click_on "Modifier" }
    assert_selector "h1", text: "Modifier « Web »"
  end
end
