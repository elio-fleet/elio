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

  test "the server's journal is searched while typing; its export follows the filter and the search" do
    server = servers(:web)
    server.notes.create!(body: "Disk **replaced**", user: users(:one))
    Activity.record!(:key_added, server: server, public_key: public_keys(:alice), unix_user: "deploy")
    visit server_path(server, tab: "journal", show: "access")
    assert_selector "#server-activity li.activity", count: 1

    find("#server-journal .journal-search input[name=q]").fill_in(with: "nothing like this")
    assert_selector "#server-activity", text: "Aucun résultat"
    find("#server-journal .journal-search input[name=q]").fill_in(with: "alice")
    assert_selector "#server-activity li.activity", count: 1

    # Catch the export instead of letting the browser save a file.
    execute_script("document.addEventListener('click', (event) => { if (event.target.closest('.export-json')) { window.exported = event.target.closest('a').href; event.preventDefault() } })")
    find("#server-journal .actions-menu summary").click
    find("a.export-json").click
    exported = URI(evaluate_script("window.exported"))
    assert_equal server_journal_path(server, format: :json), exported.path
    assert_equal({ "show" => "access", "q" => "alice" }, Rack::Utils.parse_query(exported.query).compact_blank.except("tab"))
  end
end
