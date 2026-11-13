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
    (ActivitiesController::PER_PAGE + 1).times { |index| travel_to(index.minutes.ago) { Activity.record!(:server_created, server: servers(:web)) } }
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
end
