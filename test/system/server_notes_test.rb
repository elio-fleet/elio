require "application_system_test_case"

class ServerNotesTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:viewer) }

  test "write a note with a preview, edit it in place, delete it" do
    visit server_path(servers(:web), tab: "journal")
    assert_no_selector "article.server-note"

    fill_in "Note", with: "Front **nginx**\n\n- reload: `systemctl reload nginx`"
    click_on "Aperçu"
    within("#note-preview-new .note-preview") do
      assert_selector "strong", text: "nginx"
      assert_selector "li code", text: "systemctl reload nginx"
    end
    assert_current_path server_path(servers(:web), tab: "journal")

    click_on "Ajouter la note"
    assert_selector "#flash .toast", text: "Note ajoutée."
    assert_selector "article.server-note .note-body strong", text: "nginx"
    assert_field "Note", with: ""

    within("article.server-note") { click_on "Modifier" }
    within("ul.server-notes") do
      fill_in "Note", with: "Front **apache**"
      click_on "Enregistrer"
    end
    assert_selector "article.server-note .note-body strong", text: "apache"
    assert_selector "article.server-note .note-edited"
    assert_no_selector "ul.server-notes textarea"

    accept_app_confirm { within("article.server-note") { click_on "Supprimer" } }
    assert_selector "#flash .toast", text: "Note supprimée."
    assert_no_selector "article.server-note"
  end
end
