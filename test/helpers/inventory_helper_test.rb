require "test_helper"

class InventoryHelperTest < ActionView::TestCase
  include UiHelper
  include IconsHelper

  test "why Debian leaves a CVE without a fix, explained on hover; nothing for another status" do
    badge = Nokogiri::HTML.fragment(distro_status_badge("postponed")).at("span")
    assert_equal "Reportée par Debian", badge.text.strip
    assert_equal "postponed", badge["data-distro-status"]
    assert_match "prochaine mise à jour", badge["title"]
    assert_nil distro_status_badge(nil)
    assert_nil distro_status_badge("unknown")
  end

  test "listen_address says what a wildcard or a loopback address means" do
    assert_equal "0.0.0.0 toutes les interfaces IPv4", Nokogiri::HTML.fragment(listen_address("0.0.0.0")).text
    assert_match "toutes les interfaces (IPv6", listen_address("::")
    assert_equal "* toutes les interfaces", Nokogiri::HTML.fragment(listen_address("*")).text
    assert_match "cette machine seulement", listen_address("127.0.0.53")
    assert_match "cette machine seulement", listen_address("::1")
    assert_equal "10.0.0.5", Nokogiri::HTML.fragment(listen_address("10.0.0.5")).text
  end

  test "labels" do
    assert_equal "Machine physique", virtualization_label("none")
    assert_equal "Conteneur LXC", virtualization_label("lxc")
    assert_equal "Bhyve", virtualization_label("bhyve")
    assert_equal "Inconnue", virtualization_label(nil)
    assert_equal "sudo sans mot de passe", privilege_label("sudo")
    assert_equal "inconnu", privilege_label(nil)
    assert_equal "31,3 Go", human_bytes(32_858_112 * 1024)
    assert_equal "—", human_bytes(nil)
  end

  test "end_of_life_badge warns only when the end is near or past" do
    travel_to Date.new(2026, 10, 31) do
      render html: end_of_life_badge("debian", "10")
      assert_select ".badge.end-of-life.bg-crit-soft", text: "Plus supporté depuis le 30 juin 2024"

      render html: end_of_life_badge("debian", "12")
      assert_select "span.end-of-life:not(.badge)", text: "support jusqu'au 30 juin 2028"

      assert_nil end_of_life_badge("alpine", "3.20")
    end
    travel_to Date.new(2026, 4, 1) do
      render html: end_of_life_badge("debian", "11")
      assert_select ".badge.end-of-life.bg-warn-soft", text: "Fin de support le 31 août 2026"
    end
  end

  test "inventory_status_badge" do
    snapshot = Inventory::Snapshot.new(status: "partial", message: "sans root")
    render html: inventory_status_badge(snapshot)
    assert_select ".inventory-status[title='sans root']", text: "Partiel"

    assert_nil inventory_status_badge(Inventory::Snapshot.new(status: "ok"))
    assert_nil inventory_status_badge(nil)
  end

  test "short_os_name keeps the distribution and its version" do
    assert_equal "Debian 12", short_os_name("Debian GNU/Linux 12 (bookworm)")
    assert_equal "Ubuntu 24.04.1 LTS", short_os_name("Ubuntu 24.04.1 LTS")
    assert_equal "", short_os_name(nil)
  end

  test "what a container reaches of the host: risks, ports with their exposure, networks and mounts" do
    container = { "privileged" => true, "networks" => %w[host], "mounts" => [ { "type" => "tmpfs", "destination" => "/run" } ],
                  "ports" => [ { "address" => "::1", "port" => 9000, "target" => "9000/tcp", "exposure" => "loopback" },
                               { "address" => "192.0.2.10", "port" => 53, "target" => "53/udp", "exposure" => "address" } ] }

    assert_includes container_risk_badges(container), "privilégié"
    assert_not_includes container_risk_badges(container), "socket Docker"
    assert_equal "[::1]:9000→9000/tcp local, 192.0.2.10:53→53/udp une adresse", strip_tags(container_ports(container))
    assert_equal "réseaux : host · montages : tmpfs:/run", strip_tags(container_attachments(container))
    assert_nil container_ports({})
    assert_nil container_attachments({})
    assert_equal "", container_risk_badges({})
  end
end
