require "test_helper"
require "csv"

# The fleet list: sorted by a column, the columns each user shows, and the
# CSV export of what the filters keep.
class ServersListTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  setup do
    sign_in users(:viewer)
    health(:web, load: 10, memory: 61, disk: 48, updates: { "total" => 3, "security" => 0 })
    health(:db, load: 80, memory: 20, disk: 94, updates: { "total" => 1, "security" => 1 })
    servers(:db).update_columns(reachable: true, health_status: "crit", health_reasons: [ { "tone" => "crit", "text" => "=cmd|' /C calc'!A0" } ])
  end

  def health(name, load:, memory:, disk:, updates:)
    servers(name).inventory_snapshots.create!(category: "health", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                              data: { "load_percent" => load, "memory" => { "used_percent" => memory }, "disk_max_percent" => disk, "updates" => updates })
  end

  def names = css_select("#servers tbody tr td.server-name > a").map(&:text)

  test "by name by default, then by a column: the biggest first, the servers without inventory last" do
    get servers_path
    assert_equal %w[Backup Database Web], names
    assert_select "th[aria-sort]", 0

    get servers_path(sort: "disk")
    assert_equal %w[Database Web Backup], names
    assert_select "th[aria-sort=descending] a.sort-header[href=?]", servers_path(sort: "disk", dir: "asc"), text: /Disque/

    get servers_path(sort: "disk", dir: "asc")
    assert_equal %w[Web Database Backup], names, "no inventory: last whatever the direction"

    get servers_path(sort: "updates")
    assert_equal %w[Database Web Backup], names, "the security updates first"

    get servers_path(sort: "name", dir: "desc")
    assert_equal %w[Web Database Backup], names
  end

  test "the order is kept by the filters, and an unknown column is ignored" do
    get servers_path(sort: "load", state: "crit")
    assert_select "a.filter-chip[href=?]", servers_path(sort: "load", dir: "desc")
    assert_select "form.fleet-filters input[type=hidden][name=sort][value=load]"

    get servers_path(sort: "password")
    assert_response :success
    assert_equal %w[Backup Database Web], names
  end

  test "the columns hidden by a user are not shown to them only" do
    users(:viewer).hide_fleet_columns!(%w[load notes])

    get servers_path
    assert_select "#servers .server-load", 0
    assert_select "#servers .server-notes", 0
    assert_select "#servers .server-disk", 3
    assert_select "#fleet-column-load:not([checked])"
    assert_select "#fleet-column-disk[checked]"

    sign_in users(:one)
    get servers_path
    assert_select "#servers .server-load", 3
  end

  test "choosing the columns saves them on the account and goes back to the list with its filters" do
    patch server_columns_path, params: { columns: %w[memory disk bogus] }, headers: { "HTTP_REFERER" => servers_url(state: "crit", sort: "disk", dir: "asc") }

    assert_redirected_to servers_url(state: "crit", sort: "disk", dir: "asc")
    assert_equal %w[system load updates notes], users(:viewer).reload.hidden_fleet_columns

    patch server_columns_path, params: { columns: User::FLEET_COLUMNS }
    assert_empty users(:viewer).reload.hidden_fleet_columns
  end

  test "the CSV export follows the filters and the order, not the page, and neutralises formulas" do
    get servers_path(format: :csv, sort: "disk")

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment; filename="elio-servers-\d{4}-\d{2}-\d{2}\.csv"/, response.headers["Content-Disposition"])
    rows = CSV.parse(response.body, headers: true)
    assert_equal %w[Database Web Backup], rows.map { |row| row["name"] }
    db = rows.first
    assert_equal [ "db.example.com", "2222", "admin", "crit", "80", "20", "94", "1", "1" ],
                 db.values_at("host", "port", "username", "state", "load_percent", "memory_percent", "disk_percent", "updates", "security_updates")
    assert_equal "'=cmd|' /C calc'!A0", db["reasons"]
    assert_equal "Production", rows[1]["groups"]

    get servers_path(format: :csv, state: "crit")
    assert_equal %w[Database], CSV.parse(response.body, headers: true).map { |row| row["name"] }
  end

  test "the export is in the menu of the page, with the filters, for every role" do
    get servers_path(state: "crit", sort: "disk")
    assert_select "#fleet-actions a.export-csv[href=?][data-turbo=false]", servers_path(state: "crit", sort: "disk", dir: "desc", format: :csv)
  end
end
