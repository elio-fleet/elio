require "test_helper"

class ActivitiesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "requires authentication" do
    get activities_path
    assert_redirected_to new_user_session_path
  end

  test "lists activities, most recent first, with author and server" do
    travel_to(1.hour.ago) { Activity.record!(:server_created, server: servers(:web)) }
    Activity.record!(:key_added, server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy", user: users(:one))
    sign_in users(:one)

    get activities_path

    assert_select "#activities li.activity", 2
    assert_select "#activities li.activity:first-child[data-kind=key_added]" do
      assert_select "p", text: "« Alice » ajoutée sur « Web »"
      assert_select "p", text: /Clé ajoutée\s+· one@example.com/
      assert_select "a[href=?]", server_path(servers(:web))
      assert_select ".severity-info"
    end
    assert_select "nav.main-nav a[aria-current=page]", text: "Journal"
  end

  test "filters by category" do
    Activity.record!(:key_added, server: servers(:web))
    Activity.record!(:unknown_key_detected, server: servers(:web))
    sign_in users(:one)

    get activities_path(category: "security")

    assert_select "li.activity", 1
    assert_select "li.activity[data-kind=unknown_key_detected] .severity-warning"
    assert_select ".activity-filters a[aria-current=true]", text: "Sécurité"
  end

  test "ignores an unknown category" do
    Activity.record!(:key_added, server: servers(:web))
    sign_in users(:one)

    get activities_path(category: "nope")

    assert_select "li.activity", 1
    assert_select ".activity-filters a[aria-current=true]", text: "Tout"
  end

  test "filters by server" do
    Activity.record!(:key_added, server: servers(:web))
    Activity.record!(:key_added, server: servers(:db))
    sign_in users(:one)

    get activities_path(server_id: servers(:db).id)

    assert_select "li.activity", 1
    assert_select "p", text: /sur « Database »/
  end

  test "paginates" do
    # (servers in turn: the same event repeated in a row would show once)
    (ActivitiesController::PER_PAGE + 1).times { |index| travel_to(index.minutes.ago) { Activity.record!(:server_created, server: servers(index.even? ? :web : :db)) } }
    sign_in users(:one)

    get activities_path(category: "servers")
    assert_select "li.activity", ActivitiesController::PER_PAGE
    assert_select "nav.pagination .pagination-info", "1–#{ActivitiesController::PER_PAGE} sur #{ActivitiesController::PER_PAGE + 1} activités"
    assert_select "nav.pagination a[rel=next][href=?]", activities_path(category: "servers", page: 2) # (the filters are kept)
    assert_select "nav.pagination [aria-current=page]", "1"

    get activities_path(category: "servers", page: 2)
    assert_select "li.activity", 1
    assert_select "nav.pagination a[rel=prev][href=?]", activities_path(category: "servers", page: 1)
    assert_select "nav.pagination a[rel=next]", 0
  end

  test "no pagination on a single page" do
    Activity.record!(:server_created, server: servers(:web))
    sign_in users(:one)
    get activities_path
    assert_select "nav.pagination", 0
  end

  test "empty state" do
    sign_in users(:one)
    get activities_path
    assert_select "p", text: "Aucune activité pour le moment."
  end

  test "the journal has two tabs: events and runs" do
    sign_in users(:viewer)
    get activities_path
    assert_select "nav.journal-tabs a.tab[aria-current=page][data-tab=events]", text: "Événements"
    assert_select "nav.journal-tabs a.tab[data-tab=runs][href=?]", tasks_path, text: /Exécutions/
    assert_select "h1", "Journal"

    get tasks_path
    assert_select "nav.journal-tabs a.tab[aria-current=page][data-tab=runs]"
    assert_select "nav.main-nav a[aria-current=page]", text: "Journal"
  end

  test "searches the text (data, server, key, kind label without accents) and the period, within the filters, kept in the links" do
    travel_to(Time.zone.parse("2026-11-02 10:00")) { Activity.record!(:service_failed, server: servers(:web), service: "nginx.service") }
    travel_to(Time.zone.parse("2026-11-10 10:00")) { Activity.record!(:service_failed, server: servers(:db), service: "postgresql.service") }
    travel_to(Time.zone.parse("2026-11-12 10:00")) { Activity.record!(:key_added, server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy", user: users(:one)) }
    sign_in users(:one)

    get activities_path(q: "nginx")
    assert_select "#activities li.activity", 1
    assert_select ".journal-search-count", "1 résultat"
    assert_select ".journal-search input[name=q][value=nginx]"

    get activities_path(q: "alice")
    assert_select "#activities li.activity[data-kind=key_added]", 1

    get activities_path(q: "cle ajoutee")
    assert_select "#activities li.activity[data-kind=key_added]", 1

    get activities_path(q: servers(:db).name)
    assert_select "#activities li.activity", 1

    get activities_path(q: "service", from: "2026-11-05", to: "2026-11-11")
    assert_select "#activities li.activity", 1
    assert_select "#activities li.activity p", text: /postgresql/

    get activities_path(q: "nginx", category: "keys")
    assert_select "#activities li.activity", 0
    assert_select "#search-results p", text: "Rien ne correspond à cette recherche."
    assert_select ".activity-filters a[href=?]", activities_path(q: "nginx"), text: "Tout"
    assert_select ".journal-search input[type=hidden][name=category][value=keys]"
    assert_select "a.journal-search-clear[href=?]", activities_path(category: "keys")
  end

  test "an invalid date or a text with LIKE wildcards is harmless" do
    Activity.record!(:server_created, server: servers(:web))
    sign_in users(:one)

    get activities_path(q: "%_", from: "nope", to: "2026-13-45")
    assert_response :success
    assert_select "#activities li.activity", 0
  end

  test "filters by minimum severity and kind, combined with the category, the server and the search, all kept in the links" do
    Activity.record!(:key_added, server: servers(:web))
    Activity.record!(:unknown_key_detected, server: servers(:web))
    Activity.record!(:ssh_access_lost, server: servers(:web))
    Activity.record!(:ssh_access_lost, server: servers(:db))
    sign_in users(:one)

    get activities_path(severity: "warning")
    assert_select "#activities li.activity", 3
    assert_select "#activities li.activity[data-kind=key_added]", 0
    assert_select "select#journal-severity option[selected][value=warning]"

    get activities_path(severity: "critical", server_id: servers(:web).id)
    assert_select "#activities li.activity", 1
    assert_select "#activities li.activity[data-kind=ssh_access_lost]"

    get activities_path(category: "security", kind: "unknown_key_detected", severity: "warning", q: "web")
    assert_select "#activities li.activity", 1
    assert_select "select#journal-kind option[selected][value=unknown_key_detected]"
    assert_select "select#journal-kind option[value=key_added]", 0 # (only the kinds of the category)
    # A chip keeps the other filters, and the kind when it belongs to the chosen category.
    assert_select ".activity-filters a[href=?]", activities_path(severity: "warning", kind: "unknown_key_detected", q: "web"), text: "Tout"
    assert_select ".activity-filters a[href=?]", activities_path(category: "keys", severity: "warning", q: "web"), text: "Clés SSH"
    assert_select "a.export-csv[href=?]", activities_path(category: "security", severity: "warning", kind: "unknown_key_detected", q: "web", format: :csv)
    assert_select "a.journal-search-clear[href=?]", activities_path(category: "security", severity: "warning", kind: "unknown_key_detected")

    get activities_path(severity: "info", kind: "nope")
    assert_select "#activities li.activity", 4 # (unknown values are ignored)
  end

  test "the links of the overview keep working: a server, a kind, the failed runs" do
    Activity.record!(:server_unreachable, server: servers(:web))
    Activity.record!(:server_unreachable, server: servers(:db))
    sign_in users(:viewer)

    get activities_path(server_id: servers(:web).id)
    assert_select "#activities li.activity", 1
    get activities_path(kind: "server_unreachable")
    assert_select "#activities li.activity", 2
    get tasks_path(status: "failed")
    assert_response :success
    assert_select "nav.journal-tabs a.tab[aria-current=page][data-tab=runs]"
  end

  test "exports the filtered events as CSV and JSON, formulas neutralised" do
    travel_to(Time.zone.parse("2026-11-02 10:00")) { Activity.record!(:service_failed, server: servers(:web), service: "=cmd|' /C calc'!A0") }
    Activity.record!(:key_added, server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy", user: users(:one))
    sign_in users(:viewer)

    get activities_path(category: "servers", format: :csv)
    assert_response :success
    assert_match %r{attachment; filename="elio-journal-\d{4}-\d{2}-\d{2}\.csv"}, response.headers["Content-Disposition"]
    rows = CSV.parse(response.body)
    assert_equal ActivityExport::HEADERS, rows.first
    assert_equal 2, rows.size
    row = ActivityExport::HEADERS.zip(rows.last).to_h
    assert_equal "service_failed", row["kind"]
    assert_equal "warning", row["severity"]
    assert_equal servers(:web).name, row["server"]
    assert_match %r{/journal/\d+\z}, row["url"]

    get activities_path(q: "alice", format: :json)
    json = JSON.parse(response.body)
    assert_equal 1, json["count"]
    assert_equal false, json["truncated"]
    assert_equal({ "q" => "alice" }, json["filters"])
    event = json["events"].first
    assert_equal [ "key_added", "one@example.com", "deploy", "Alice" ], event.values_at("kind", "author", "unix_user", "public_key")
    assert_equal activity_url(Activity.find(event["id"])), event["url"]
  end

  test "one event on its own page, linked from the list" do
    activity = Activity.record!(:key_added, server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy", user: users(:one))
    sign_in users(:viewer)

    get activities_path
    assert_select "#activities a.activity-permalink[href=?]", activity_path(activity)

    get activity_path(activity)
    assert_select "h1", "« Alice » ajoutée sur « Web »"
    assert_select "#activity-details dd", text: /Clé ajoutée/
    assert_select "#activity-details a[href=?]", server_path(servers(:web))
    assert_select "#activity-details a[href=?]", public_key_path(public_keys(:alice))
    assert_select "#activity-details dd", text: "deploy"
    assert_select "a.same-kind[href=?]", activities_path(kind: "key_added", server_id: servers(:web).id)

    get activity_path(id: 0)
    assert_response :not_found
  end

  test "an event repeated in a row shows once, with its count and the times of the others" do
    3.times { |index| travel_to((10 - index).minutes.ago) { Activity.record!(:container_restarting, server: servers(:web), container: "api") } }
    travel_to(5.minutes.ago) { Activity.record!(:container_restarting, server: servers(:db), container: "api") }
    Activity.record!(:container_restarting, server: servers(:web), container: "api")
    sign_in users(:one)

    get activities_path

    assert_select "#activities > li.activity", 3
    assert_select "#activities > li.activity:first-child .activity-repeats", 0
    assert_select "#activities > li.activity:last-child .activity-repeats", text: "× 3"
    assert_select "#activities > li.activity:last-child .activity-repeat-list a", 2
  end
end
