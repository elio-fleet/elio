require "test_helper"

# Signed packages (Secure Boot) have a version of their own, not the one of
# the code they sign: compared as such with the fixed version of the feeds,
# grub-efi-amd64-signed 1+2.12+9+deb13u2 looked older than grub2's fix 2.12-6
# (Yanis's false "not up to date", phase 13.3).
class Vulnerabilities::SignedPackagesTest < ActiveSupport::TestCase
  include VulnerabilityHelpers
  include PackageHelpers

  Matcher = Vulnerabilities::Matcher
  Packages = Inventory::Collectors::Packages

  # Real dpkg-query lines of the Debian 13 test VMs (with Built-Using); the
  # EFI ones (not installed on these BIOS VMs) are built from the real
  # `apt-cache show` of the same repositories.
  def signed_dpkg = file_fixture("inventory/packages/signed-debian13.txt").read

  test "Built-Using gives the code a signed package signs" do
    assert_equal [ "grub2", "2.12-9+deb13u2" ], Matcher.signed_source("grub-efi-amd64-signed", "1+2.12+9+deb13u2", "grub2 (= 2.12-9+deb13u2)")
    assert_equal [ "shim", "16.1-2~deb13u1" ], Matcher.signed_source("shim-signed", "1.51~1+deb13u1+16.1-2~deb13u1", "shim (= 16.1-2~deb13u1)")
    assert_equal [ "fwupd-efi", "1:1.7-1" ], Matcher.signed_source("fwupd-amd64-signed", "1:1.7+1", "fwupd-efi (= 1:1.7-1)")
    assert_equal [ "linux", "6.12.107-1" ], Matcher.signed_source("linux-signed-amd64", "6.12.107-1", "linux (= 6.12.107-1)")
    assert_equal [ "systemd", "257.8-1~deb13u2" ], Matcher.signed_source("systemd-boot-efi-amd64-signed", "257.8+1~deb13u2", "systemd (= 257.8-1~deb13u2)"),
                 "any other signed package"
    assert_nil Matcher.signed_source("grub2", "2.12-9+deb13u2", "lzo2 (= 2.10-3)"), "Built-Using of an unsigned package is not its source"
    assert_nil Matcher.signed_source("openssl", "3.0.15-1~deb12u1")
  end

  test "without Built-Using (older inventories, versions offered by apt), the version is deduced from the signed one" do
    assert_equal [ "grub2", "2.12-9+deb13u2" ], Matcher.signed_source("grub-efi-amd64-signed", "1+2.12+9+deb13u2")
    assert_equal [ "shim", "16.1-2~deb13u1" ], Matcher.signed_source("shim-signed", "1.51~1+deb13u1+16.1-2~deb13u1")
    assert_equal [ "fwupd-efi", "1:1.7-1" ], Matcher.signed_source("fwupd-amd64-signed", "1:1.7+1")
    assert_equal [ "linux", "6.12.113-1" ], Matcher.signed_source("linux-signed-amd64", "6.12.113-1")
    assert_nil Matcher.signed_source("systemd-boot-efi-amd64-signed", "257.8+1~deb13u2"), "unknown: left as it is"

    assert_equal "2.12-9+deb13u3", Matcher.unsigned_version("grub-efi-amd64-signed", "1+2.12+9+deb13u3")
    assert_equal "6.12.113-1", Matcher.unsigned_version("linux-image-amd64", "6.12.113-1")
    assert_equal "3.0.15-1~deb12u1", Matcher.unsigned_version("libssl3", "3.0.15-1~deb12u1")
  end

  test "the inventory stores the signed code as the source of a signed package" do
    packages = Packages.parse_dpkg(signed_dpkg, {}).index_by { |package| package["name"] }

    assert_equal [ "grub2", "2.12-9+deb13u2" ], packages["grub-efi-amd64-signed"].values_at("source", "source_version")
    assert_equal [ "shim", "16.1-2~deb13u1" ], packages["shim-signed"].values_at("source", "source_version")
    assert_equal [ "fwupd-efi", "1:1.7-1" ], packages["fwupd-amd64-signed"].values_at("source", "source_version")
    assert_equal [ "linux", nil ], packages["linux-image-6.12.107+deb13-amd64"].values_at("source", "source_version"), "the binary version is linux's"
    assert_equal [ "linux", nil ], packages["linux-image-amd64"].values_at("source", "source_version")
    assert_equal [ "grub2", nil ], packages["grub-common"].values_at("source", "source_version"), "Built-Using of lzo2 ignored"
    assert_equal [ nil, nil ], packages["fwupd"].values_at("source", "source_version")
  end

  test "an image's dpkg status file gives Built-Using too" do
    status = <<~STATUS
      Package: shim-signed
      Status: install ok installed
      Source: shim-signed (1.51~1+deb13u1)
      Version: 1.51~1+deb13u1+16.1-2~deb13u1
      Built-Using: shim (= 16.1-2~deb13u1)

      Package: grub-common
      Status: install ok installed
      Source: grub2
      Version: 2.12-9+deb13u2
      Built-Using: lzo2 (= 2.10-3)
    STATUS
    assert_equal [ [ "shim-signed", "shim", "16.1-2~deb13u1" ], [ "grub-common", "grub2", "2.12-9+deb13u2" ] ],
                 Inventory::Collectors::Docker.parse_dpkg_status(status).map { |package| package.to_h.values }
  end

  test "grub2's fix 2.12-6 does not affect grub 2.12-9+deb13u2, signed or not" do
    record_os(servers(:web), codename: "trixie", version_id: "13")
    VulnerabilityFeed.for("debian").update!(releases: [ "trixie" ], refreshed_at: Time.current)
    Vulnerability.create!(source: "debian", release: "trixie", package: "grub2", cve: "CVE-2023-4692", fixed_version: "2.12-6", severity: "high")
    Vulnerability.create!(source: "debian", release: "trixie", package: "grub2", cve: "CVE-2025-0001", fixed_version: "2.12-9+deb13u3", severity: "high")

    # A new inventory (Built-Using) and an older one (no Built-Using, signed source only).
    [ Packages.parse_dpkg(signed_dpkg, {}),
      [ dpkg("grub-efi-amd64-signed", "1+2.12+9+deb13u2"), dpkg("grub-common", "2.12-9+deb13u2", source: "grub2") ] ].each do |list|
      record_packages(servers(:web), list.map { |package| package.merge("available_version" => nil) })
      Matcher.call(servers(:web))
      grub = servers(:web).server_vulnerabilities.where(source_package: "grub2")
      assert_equal [ "CVE-2025-0001" ], grub.pluck(:cve)
      assert_equal [ "2.12-9+deb13u2" ], grub.pluck(:installed_version)
    end
  end

  test "the fix of a signed package offered by apt counts as available" do
    record_os(servers(:web), codename: "trixie", version_id: "13")
    VulnerabilityFeed.for("debian").update!(releases: [ "trixie" ], refreshed_at: Time.current)
    Vulnerability.create!(source: "debian", release: "trixie", package: "grub2", cve: "CVE-2025-0001", fixed_version: "2.12-9+deb13u3", severity: "high")
    list = Packages.parse_dpkg(signed_dpkg, {}).select { |package| package["name"].start_with?("grub") }
    list.each { |package| package["available_version"] = package["name"] == "grub-efi-amd64-signed" ? "1+2.12+9+deb13u3" : "2.12-9+deb13u3" }
    record_packages(servers(:web), list)
    Matcher.call(servers(:web))

    group = PackageVulnerabilities.new(servers(:web).server_vulnerabilities, server: servers(:web)).groups.sole
    assert_equal :available, group.state
    assert_equal %w[grub-common grub-efi-amd64-bin grub-efi-amd64-signed grub-pc], group.upgrade_packages.sort
  end
end
