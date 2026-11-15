require "test_helper"

class Vulnerabilities::ReferencesTest < ActiveSupport::TestCase
  test "keeps the Debian and Ubuntu advisories and the fixes, advisories first, without duplicates" do
    entries = [
      { "url" => "https://github.com/openssh/openssh-portable/commit/81c1099d22b81ebfd20a334ce986c4f753b0db29", "tags" => [] },
      { "url" => "https://www.debian.org/security/2024/dsa-5724", "tags" => [ "Third Party Advisory" ] },
      { "url" => "https://lists.debian.org/debian-lts-announce/2024/07/msg00001.html" },
      { "url" => "https://ubuntu.com/security/notices/USN-6859-1" },
      { "url" => "http://www.openwall.com/lists/oss-security/2024/07/03/3", "tags" => [ "Mailing List", "Patch" ] },
      { "url" => "https://www.qualys.com/2024/07/01/cve-2024-6387/regresshion.txt", "tags" => [] },
      { "url" => "https://access.redhat.com/errata/RHSA-2024:4312", "tags" => [ "vendor-advisory" ] },
      { "url" => "javascript:alert(1)", "tags" => [ "Patch" ] },
      { "url" => "https://www.debian.org/security/2024/dsa-5724" },
      "not a hash"
    ]

    picked = Vulnerabilities::References.pick(entries)

    assert_equal %w[advisory advisory advisory fix fix], picked.map { |reference| reference["kind"] }
    assert_equal [ "https://www.debian.org/security/2024/dsa-5724", "https://lists.debian.org/debian-lts-announce/2024/07/msg00001.html",
                   "https://ubuntu.com/security/notices/USN-6859-1" ], picked.first(3).map { |reference| reference["url"] }
    assert_empty Vulnerabilities::References.pick(nil)
    assert_equal Vulnerabilities::References::LIMIT, Vulnerabilities::References.pick(Array.new(30) { |i| { "url" => "https://example.test/#{i}.patch" } }).size
  end

  test "a short label for each link" do
    labels = %w[https://www.debian.org/security/2024/dsa-5724 https://www.debian.org/security/2024/dla-3842-1
                https://ubuntu.com/security/notices/USN-6859-1 https://lists.debian.org/debian-lts-announce/2024/07/msg00001.html
                https://github.com/openssh/openssh-portable/commit/81c1099d22b81ebfd20a334ce986c4f753b0db29].map { |url| Vulnerabilities::References.label(url) }

    assert_equal [ "DSA-5724", "DLA-3842-1", "USN-6859-1", "Debian LTS (2024-07)" ], labels.first(4)
    assert_match(/\Agithub\.com · commit\/81c1099d/, labels.last)
  end

  test "the references of a CVE come from all its stored scores" do
    CveScore.store("nvd", [ { cve: "CVE-2024-6387", score: 8.1, data: { "references" => [ { "url" => "https://x.test/a.patch", "kind" => "fix" } ] } } ])
    CveScore.store("cveorg", [ { cve: "CVE-2024-6387", score: 8.1, data: { "references" => [ { "url" => "https://x.test/a.patch", "kind" => "fix" },
                                                                                                { "url" => "https://ubuntu.com/security/notices/USN-1-1", "kind" => "advisory" } ] } } ])

    references = Vulnerabilities::References.of(CveScore.where(cve: "CVE-2024-6387").order(:provider_key))

    assert_equal [ "https://ubuntu.com/security/notices/USN-1-1", "https://x.test/a.patch" ], references.map { |reference| reference["url"] }
  end
end
