require "test_helper"

# Outputs captured on a real Debian 13 server (anonymized), parsed by every
# collector: guards against formats that the handwritten samples missed.
class Inventory::Collectors::RealDebian13Test < ActiveSupport::TestCase
  def output(name) = file_fixture("inventory/debian13-real/#{name}.txt").read

  def sections(name) = Inventory::Collector.sections(output(name))

  test "system" do
    os = Inventory::Collectors::Os.parse(output(:os))

    assert_equal [ "Debian GNU/Linux 13 (trixie)", "debian", "13", "trixie", "db-1.example.internal", 4 ],
                 os.values_at("name", "id", "version_id", "codename", "hostname", "cpus")
    assert_match(/\A6\.12\./, os["kernel"])
    assert Inventory::EndOfLife.status(os["id"], os["version_id"]).known?
  end

  test "health" do
    health = Inventory::Collectors::Health.parse(output(:health))

    assert_equal 4, health["cpus"]
    assert health["memory"]["used_percent"].between?(0, 100)
    assert health["disks"].any? { |disk| disk["mount"] == "/" }
    assert_equal false, health["ntp_synchronized"]
    assert_equal({ "total" => 33, "security" => 10 }, health["updates"])
  end

  test "packages" do
    packages = Inventory::Collectors::Packages
    data = packages.summarize(packages.parse_dpkg(sections(:packages)["dpkg"], packages.parse_upgradable(sections(:packages)["upgradable"])))

    assert_equal [ 631, 33, 10 ], data.values_at("total", "upgradable", "security")
    assert data["packages"].any? { |package| package["name"] == "openssh-server" }
  end

  test "services" do
    services = Inventory::Collectors::Services
    # Read before the unit details were collected: units only.
    units = services.parse_units(sections(:services)["units"], services.parse_unit_details(sections(:services)["unit-details"]))

    assert_equal 107, units.size
    assert_equal "running", units.find { |unit| unit["name"] == "ssh.service" }["sub"]
  end

  test "ports and firewall" do
    data = Inventory::Collectors::Ports.parse(sections(:ports))

    assert_equal 17, data["listening"].size
    assert_includes data["listening"].map { |entry| [ entry["port"], entry["process"] ] }, [ 5432, "postgres" ]
    assert data["listening"].all? { |entry| entry["unit"].present? || entry["process"].present? }
    assert_equal({ "tool" => "none", "active" => false }, data["firewall"])
  end
end
