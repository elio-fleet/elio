require "test_helper"
require "csv"

class ServerJournalsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @server = servers(:web)
    @note = @server.notes.create!(body: "Rebooted after the kernel update", user: users(:one))
    @key = Activity.record!(:key_added, server: @server, public_key: public_keys(:alice), unix_user: "deploy")
    Activity.record!(:key_added, server: servers(:db), public_key: public_keys(:alice), unix_user: "admin")
  end

  test "exports the server's notes and events as CSV, a viewer too" do
    sign_in users(:viewer)

    get server_journal_path(@server, format: :csv)

    assert_response :success
    assert_match %r{attachment; filename="elio-journal-web-\d{4}-\d{2}-\d{2}\.csv"}, response.headers["Content-Disposition"]
    rows = CSV.parse(response.body).drop(1).map { |row| ActivityExport::HEADERS.zip(row).to_h }
    assert_equal %w[key_added server_note], rows.pluck("kind")
    assert_equal activity_url(@key), rows.first["url"]
    assert_equal server_url(@server, tab: "journal", anchor: "server_note_#{@note.id}"), rows.last["url"]
  end

  test "the JSON follows the filter and the search of the tab" do
    sign_in users(:one)

    get server_journal_path(@server, show: "notes", q: "kernel", format: :json)

    json = JSON.parse(response.body)
    assert_equal({ "server" => "Web", "show" => "notes", "q" => "kernel" }, json["filters"])
    assert_equal [ [ "server_note", "Rebooted after the kernel update" ] ], json["events"].map { |event| event.values_at("kind", "summary") }
  end

  test "the page itself is the Journal tab of the server" do
    sign_in users(:one)

    get server_journal_path(@server, show: "access")

    assert_redirected_to server_path(@server, tab: "journal", show: "access")
  end
end
