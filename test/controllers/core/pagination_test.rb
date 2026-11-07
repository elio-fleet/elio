require "test_helper"

# Every long list is paged (shared/_pagination), keeping its filters.
class PaginationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier
  include PackageHelpers
  include PortHelpers

  # Lowers a PER_PAGE constant for the test.
  def with_per_page(klass, value, name: :PER_PAGE)
    original = klass.const_get(name)
    klass.send(:remove_const, name)
    klass.const_set(name, value)
    yield
  ensure
    klass.send(:remove_const, name)
    klass.const_set(name, original)
  end

  setup { sign_in users(:one) }

  # Query of the "next page" link, whatever the parameters order.
  def next_page_query
    href = css_select("nav.pagination a[rel=next]").first&.[]("href")
    assert href, "no next page link"
    Rack::Utils.parse_query(URI(href).query)
  end

  test "fleet, with the filters kept" do
    with_per_page(ServersController, 2) do
      get servers_path(os: nil)
      assert_select "#servers tbody tr", 2
      assert_select "nav.pagination .pagination-info", "1–2 sur 3 serveurs"

      get servers_path(page: 2)
      assert_select "#servers tbody tr", 1
      assert_select "#servers tbody tr", text: /Web/
    end
  end

  test "keyring, with the kind filter kept" do
    with_per_page(PublicKeysController, 1) do
      PublicKey.create!(name: "Bob", kind: "person", content: Ssh::KeyGenerator.generate(comment: "bob").public_key)
      get public_keys_path(kind: "person")
      assert_equal({ "kind" => "person", "page" => "2" }, next_page_query)
    end
  end

  test "users" do
    with_per_page(Settings::UsersController, 2) do
      get settings_users_path
      assert_select "li.user-row", 2
      assert_select "nav.pagination .pagination-info", "1–2 sur #{User.count} utilisateurs"
    end
  end

  test "public ports" do
    record_ports(servers(:web))
    record_ports(servers(:db))
    with_per_page(PortsController, 1) do
      get ports_path
      assert_select "tr.public-port", 1
      assert_select "nav.pagination a[rel=next]"
    end
  end

  test "fleet packages: search results and security updates, by package name" do
    packages = %w[libssl3 openssl ssl-cert].map { |name| { manager: "dpkg", name: name, version: "1", arch: "amd64", available_version: "2", security: true } }
    record_packages(servers(:web), packages)
    record_packages(servers(:db), packages.first(1))

    with_per_page(PackagesController, 2, name: :RESULTS_PER_PAGE) do
      get packages_path(q: "ssl")
      assert_select "section.package-result", 2
      assert_select "section.package-result h2", text: /libssl3|openssl/
      assert_equal({ "q" => "ssl", "page" => "2" }, next_page_query)

      get packages_path(q: "ssl", page: 2)
      assert_select "section.package-result", 1
      assert_select "section.package-result h2", text: /ssl-cert/
    end

    with_per_page(PackagesController, 1, name: :SECURITY_PER_PAGE) do
      get packages_path
      assert_select "tr.security-update", 1
      assert_select ".security-updates .card-header", text: /3 paquets/
      assert_select ".security-updates nav.pagination"
    end
  end

  test "a server's packages page inside their frame" do
    record_packages(servers(:web), %w[a b c].map { |name| { manager: "dpkg", name: name, version: "1", arch: "amd64" } })
    with_per_page(ServerPackagesController, 2) do
      get server_packages_path(servers(:web), q: "")
      assert_select "turbo-frame##{dom_id(servers(:web), :packages)} nav.pagination"
      assert_equal({ "q" => "", "page" => "2" }, next_page_query)
    end
  end

  test "a server's history" do
    3.times { Activity.record!(:server_created, server: servers(:web)) }
    with_per_page(ServersController, 2, name: :HISTORY_PER_PAGE) do
      get server_path(servers(:web), tab: "journal")
      assert_select "#server-activity li.activity", 2
      assert_select "#server-activity a[href=?]", server_path(servers(:web), tab: "journal", page: 2), text: /Plus anciens/

      get server_path(servers(:web), tab: "journal", page: 2)
      assert_select "#server-activity li.activity", 1
      assert_select "#server-activity a", text: /Plus anciens/, count: 0
    end
  end

  test "the notes of a server" do
    3.times { |index| servers(:web).notes.create!(body: "Note #{index}", user: users(:one), created_at: index.minutes.ago) }
    sign_in users(:one)
    with_per_page(ServersController, 2, name: :HISTORY_PER_PAGE) do
      get server_path(servers(:web), tab: "journal", show: "notes", page: 2)
    end
    assert_select "article.server-note", 1
    assert_select "article.server-note .note-body", "Note 2"
    assert_select "#server-activity a[href=?]", server_path(servers(:web), tab: "journal", show: "notes"), text: /Plus récents/
  end
end
