require "test_helper"

class CommandSearchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PackageHelpers

  setup { sign_in users(:viewer) }

  def results(query)
    get command_search_path(q: query)
    assert_response :success
    response.parsed_body["results"].map { |result| result.values_at("group", "label", "hint", "url") }
  end

  def vulnerable(server, cve, origin: "host")
    server.server_vulnerabilities.create!(origin: origin, source: "debian", image: origin == "image" ? "nginx:1" : nil, cve: cve, source_package: "openssl",
                                          installed_version: "1", fixed_version: "2", severity: "high")
  end

  test "finds the fleet's CVEs by a part of their id, with their number of servers" do
    vulnerable(servers(:web), "CVE-2024-9143")
    vulnerable(servers(:web), "CVE-2024-9143", origin: "image")
    vulnerable(servers(:db), "CVE-2024-9143")
    vulnerable(servers(:db), "CVE-2023-1111")

    assert_equal [ [ "CVE", "CVE-2024-9143", "2 serveurs", vulnerability_path("CVE-2024-9143") ] ], results("cve-2024-91")
    assert_equal [ [ "CVE", "CVE-2023-1111", "1 serveur", vulnerability_path("CVE-2023-1111") ] ], results("2023-11")
  end

  test "an exact CVE known only from the feeds opens its page; an unknown one gives nothing" do
    Vulnerability.create!(source: "debian", release: "bookworm", package: "x", cve: "CVE-2024-12345", severity: "low")

    assert_equal [ [ "CVE", "CVE-2024-12345", "absente du parc", vulnerability_path("CVE-2024-12345") ] ], results("CVE-2024-12345")
    assert_empty results("CVE-2024-99999")
  end

  test "finds packages by name, the exact name first, and never reads the CVEs for a package name" do
    record_packages(servers(:web), [ { manager: "dpkg", name: "libssh-4", version: "1" }, { manager: "dpkg", name: "openssh-client", version: "1" }, { manager: "dpkg", name: "ssh", version: "1" } ])
    record_packages(servers(:db), [ { manager: "dpkg", name: "ssh", version: "1" } ])

    assert_equal [ [ "Paquets", "ssh", "2 serveurs", packages_path(q: "ssh") ], [ "Paquets", "libssh-4", "1 serveur", packages_path(q: "libssh-4") ],
                   [ "Paquets", "openssh-client", "1 serveur", packages_path(q: "openssh-client") ] ], results("SSH")

    vulnerable(servers(:web), "CVE-2024-9143")
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { results("openssh") }
    assert_no_match(/server_vulnerabilities/, queries.join("\n"))
  end

  test "finds server notes, the latest first, and opens their server's journal" do
    servers(:db).notes.create!(body: "Restore **procedure**: see the wiki", user: users(:one))

    assert_equal [ [ "Notes", "Database", "Restore procedure: see the wiki", server_path(servers(:db), tab: "journal", show: "notes") ] ], results("procedure")
  end

  test "nothing under two characters" do
    record_packages(servers(:web), [ { manager: "dpkg", name: "x11-common", version: "1" } ])

    assert_empty results("x")
    assert_empty results(" ")
  end
end
