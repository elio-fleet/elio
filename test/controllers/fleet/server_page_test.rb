require "test_helper"

# Server page: recent port / SSH results shown as is (no login on every
# visit), the last opened tab remembered, the tab counters without
# repeated queries.
class ServerPageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  setup do
    @server = servers(:web)
    sign_in users(:one)
  end

  test "recent port and SSH results are shown without checking again, with a button to check" do
    @server.update_columns(reachable: true, last_checked_at: 1.minute.ago, ssh_ok: true, ssh_checked_at: 2.minutes.ago)

    get server_path(@server)

    assert_select "#server-health" do
      assert_select "turbo-frame##{dom_id(@server, :reachability)}:not([src])" do
        assert_select ".server-status", text: "En ligne"
        assert_select "a.health-refresh[href=?]", server_ping_path(@server)
      end
      assert_select "turbo-frame##{dom_id(@server, :ssh_check)}:not([src])" do
        assert_select ".ssh-check-result", text: /Connexion OK/
        assert_select "a.health-refresh[href=?]", server_ssh_check_path(@server)
      end
      assert_select ".health-checking", 0
    end
  end

  test "an old result, or a refused SSH login, is checked again on display" do
    @server.update_columns(reachable: false, last_checked_at: 6.minutes.ago, ssh_ok: false, ssh_checked_at: 1.minute.ago)

    get server_path(@server)

    assert_select "turbo-frame##{dom_id(@server, :reachability)}[loading=lazy][src=?]", server_ping_path(@server)
    assert_select "turbo-frame##{dom_id(@server, :ssh_check)}[loading=lazy][src=?]", server_ssh_check_path(@server)

    @server.update_columns(ssh_ok: true, ssh_checked_at: 6.minutes.ago)
    get server_path(@server)
    assert_select "turbo-frame##{dom_id(@server, :ssh_check)}[loading=lazy][src=?]", server_ssh_check_path(@server)
  end

  test "a link to a server opens the tab last opened on it, the overview tab is a way back" do
    get server_path(@server, tab: "journal")
    assert_response :success

    get server_path(@server)
    assert_redirected_to server_path(@server, tab: "journal")

    get server_path(servers(:db))
    assert_response :success, "another server keeps its own tab"
    assert_select "nav.server-tabs a[aria-current=page][data-tab=overview]"

    get server_path(@server, tab: "overview")
    assert_response :success
    get server_path(@server)
    assert_response :success
    assert_select "nav.server-tabs a[aria-current=page][data-tab=overview][href=?]", server_path(@server, tab: "overview")
  end

  test "a prefetched tab, an unknown tab or a tab that no longer exists is not opened again" do
    get server_path(@server, tab: "docker"), headers: { "X-Sec-Purpose" => "prefetch" }
    get server_path(@server, tab: "nope")
    get server_path(@server)
    assert_response :success

    cookies[:elio_server_tabs] = { @server.id.to_s => "monitors" }.to_json # extension disabled
    get server_path(@server)
    assert_response :success

    cookies[:elio_server_tabs] = "not json"
    get server_path(@server)
    assert_response :success
  end

  test "only the most recent servers are remembered" do
    tabs = (1..ServersController::REMEMBERED_TABS).to_h { |id| [ (id + 1_000_000).to_s, "journal" ] }
    cookies[:elio_server_tabs] = tabs.to_json

    get server_path(@server, tab: "keys")

    remembered = JSON.parse(cookies[:elio_server_tabs])
    assert_equal ServersController::REMEMBERED_TABS, remembered.size
    assert_equal "keys", remembered[@server.id.to_s]
    assert_not remembered.key?("1000001"), "the oldest server is forgotten"
  end

  test "the vulnerabilities tab counts the fixable CVEs once" do
    get server_path(@server, tab: "vulnerabilities")
    ActiveRecord::Base.connection.clear_query_cache
    queries = []
    counter = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?("COUNT(DISTINCT") && payload[:sql].include?("fixed_version") }

    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { get server_path(@server, tab: "vulnerabilities") }

    assert_equal 1, queries.count { |sql| sql.include?("server_vulnerabilities\".\"server_id\"") }, queries.join("\n")
  end
end
