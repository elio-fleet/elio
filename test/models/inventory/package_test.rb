require "test_helper"

class Inventory::PackageTest < ActiveSupport::TestCase
  include PackageHelpers

  test "the kind of repository a package comes from" do
    assert_equal %w[distribution distribution distribution backports third_party third_party local],
                 [ "Debian/bookworm", "Ubuntu/noble-security", "UbuntuESMApps/noble-apps-security", "Debian Backports/bookworm-backports",
                   "Docker/bookworm", "LP-PPA-ondrej-php/noble", "local" ].map { |origin| Inventory::Package.origin_kind(origin) }
    assert_nil Inventory::Package.origin_kind(nil)
    assert_equal "Hors dépôt", Inventory::Package.new(origin: "local").origin_label
    assert_equal "Docker/bookworm", Inventory::Package.new(origin: "Docker/bookworm").origin_label
  end

  test "the updates that only apply after a reboot: kernel and microcode" do
    reboot = %w[linux-image-6.1.0-28-amd64 linux-image-amd64 intel-microcode amd64-microcode].map { |name| Inventory::Package.new(name: name, available_version: "2") }
    others = %w[linux-libc-dev openssl intel-microcode-tools].map { |name| Inventory::Package.new(name: name, available_version: "2") }
    assert reboot.all?(&:reboot?)
    assert_not others.any?(&:reboot?)
    assert_not Inventory::Package.new(name: "linux-image-amd64").reboot?, "no update, no reboot"
  end

  test "outside the distribution: backports, third-party and local packages, the SQL twin of origin_kind" do
    origins = [ "Debian/bookworm", "Ubuntu/noble-updates", "Debian Backports/bookworm-backports", "Docker/bookworm", "local", nil ]
    record_packages(servers(:web), origins.each_with_index.map { |origin, index| { manager: "dpkg", name: "p#{index}", version: "1", origin: origin } })

    outside = Inventory::Package.outside_distribution.pluck(:origin)
    assert_equal [ "Debian Backports/bookworm-backports", "Docker/bookworm", "local" ], outside.sort
    assert_equal outside.sort, origins.select { |origin| %w[backports third_party local].include?(Inventory::Package.origin_kind(origin)) }.sort
  end
end
