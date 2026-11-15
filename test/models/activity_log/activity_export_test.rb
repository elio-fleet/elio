require "test_helper"
require "csv"

class ActivityExportTest < ActiveSupport::TestCase
  test "a text a spreadsheet would run as a formula is neutralised in the CSV" do
    Activity.record!(:server_deleted, server_name: "=HYPERLINK(\"http://x.test\")")

    rows = CSV.parse(ActivityExport.new(Activity.recent).to_csv)

    row = ActivityExport::HEADERS.zip(rows.last).to_h
    assert_equal "'=HYPERLINK(\"http://x.test\")", row["server"]
    assert_nil row["url"]
  end

  test "keeps the order of the scope and says when it was cut" do
    3.times { |index| travel_to(index.minutes.ago) { Activity.record!(:server_created, server: servers(:web)) } }
    newest_first = Activity.recent.pluck(:id)

    export = ActivityExport.new(Activity.recent.includes(:server), filters: { severity: nil, q: "web" })
    assert_equal newest_first, export.records.pluck("id")
    assert_not export.truncated?
    assert_equal({ "q" => "web" }, JSON.parse(export.to_json)["filters"])

    cut = ActivityExport.new(Activity.recent, limit: 2)
    assert_equal newest_first.first(2), cut.records.pluck("id")
    assert cut.truncated?
  end

  test "at_least keeps the severity asked and the more serious ones" do
    Activity.record!(:key_added)
    Activity.record!(:server_unreachable)
    Activity.record!(:ssh_access_lost)

    assert_equal %w[server_unreachable ssh_access_lost], Activity.at_least(:warning).order(:id).pluck(:kind)
    assert_equal %w[ssh_access_lost], Activity.at_least("critical").pluck(:kind)
    assert_equal 3, Activity.at_least(:info).count
  end
end
