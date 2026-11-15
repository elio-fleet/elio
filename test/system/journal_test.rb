require "application_system_test_case"

class JournalTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  test "the severity and kind filters reload the page; the export follows a search typed meanwhile; a repeated event unfolds" do
    3.times { |index| travel_to((10 - index).minutes.ago) { Activity.record!(:container_restarting, server: servers(:web), container: "api") } }
    Activity.record!(:key_added, server: servers(:web))
    sign_in users(:viewer)
    visit activities_path

    find("select#journal-severity").select("Avertissement ou plus")
    assert_no_selector "#activities li.activity[data-kind=key_added]"
    assert_current_path(/[?&]severity=warning(&|\z)/)
    # The chips follow the new filter (the whole page was reloaded, not only the list).
    assert_selector ".activity-filters a[href='#{activities_path(category: "servers", severity: "warning")}']"

    # Three times the same restart: one line, the earlier times inside.
    assert_selector "#activities li.activity", count: 1
    assert_selector ".activity-repeats", text: "× 3"
    find(".activity-repeat-list summary").click
    assert_selector ".activity-repeat-list a", count: 2

    find(".journal-search input[name=q]").fill_in(with: "api")
    assert_selector ".journal-search-count", text: "3 résultats"
    # Catch the export instead of letting the browser save a file.
    execute_script("document.addEventListener('click', (event) => { if (event.target.closest('.export-csv')) { window.exported = event.target.closest('a').href; event.preventDefault() } })")
    find(".page-header .actions-menu summary").click
    find("a.export-csv").click
    exported = URI(evaluate_script("window.exported"))
    assert_equal "/journal.csv", exported.path
    assert_equal({ "severity" => "warning", "q" => "api" }, Rack::Utils.parse_query(exported.query).compact_blank)
  end
end
