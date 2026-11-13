require "test_helper"

class Dns::CsvImportTest < ActiveSupport::TestCase
  def parse(text) = Dns::CsvImport.parse(text)

  test "lines without header, separated by commas, semicolons or tabs, with CRLF, blank lines and comments" do
    result = parse("www.Example.com,A,203.0.113.10,3600\r\n\r\n# office\nshop.example.com;cname;WWW.example.com.\nv6.example.com\tAAAA\t2001:DB8::1\n")

    assert_equal [ { zone: "example.com", name: "www.example.com", record_type: "A", value: "203.0.113.10", ttl: 3600 },
                   { zone: "example.com", name: "shop.example.com", record_type: "CNAME", value: "www.example.com", ttl: nil },
                   { zone: "example.com", name: "v6.example.com", record_type: "AAAA", value: "2001:db8::1", ttl: nil } ], result.rows
    assert_empty result.refused
    assert_equal "3 enregistrements lus, 0 ligne(s) refusée(s)", result.summary
  end

  test "a header names the columns in any order, quotes are read, the zone column is used" do
    result = parse(%(type,value,name,zone\n"A","10.0.0.5","printer.office.lan","office.lan"\nA,10.0.0.6,nas.office.lan,example.com))

    assert_equal [ { zone: "office.lan", name: "printer.office.lan", record_type: "A", value: "10.0.0.5", ttl: nil } ], result.rows
    assert_equal [ [ 3, "le nom n'est pas dans cette zone" ] ], result.refused.map { |refusal| [ refusal.line, refusal.reason ] }
  end

  test "refused lines, each with its reason; the others are kept" do
    result = parse(<<~CSV)
      mail.example.com,MX,10 mx.example.com
      bad name.example.com,A,1.2.3.4
      x.example.com,A,999.1.1.1
      x.example.com,A,10.0.0.0/8
      y.example.com,AAAA,10.0.0.1
      z.example.com,CNAME,not a host
      t.example.com,A,10.0.0.1,soon
      only-two.example.com,A
      localhost,A,127.0.0.1
      ok.example.com,A,10.0.0.1
      OK.example.com.,A,10.0.0.1
    CSV

    assert_equal [ "ok.example.com" ], result.rows.map { |row| row[:name] }
    assert_equal [ "type non pris en charge (A, AAAA ou CNAME)", "nom invalide", "adresse IPv4 invalide", "adresse IPv4 invalide", "adresse IPv6 invalide",
                   "cible CNAME invalide", "TTL invalide", "il faut au moins nom, type et valeur", "nom invalide", "déjà plus haut" ], result.refused.map(&:reason)
    assert_equal (1..11).to_a - [ 10 ], result.refused.map(&:line)
  end

  test "a wildcard name, and nothing at all" do
    assert_equal [ "*.apps.example.com" ], parse("*.apps.example.com,A,10.0.0.1").rows.map { |row| row[:name] }
    assert_equal [ [], [] ], parse(" \n# nothing\n").to_h.values
  end

  test "beyond the limit, the rest is ignored and said" do
    stub_const = Dns::CsvImport::MAX_LINES
    text = Array.new(stub_const + 2) { |index| "h#{index}.example.com,A,10.0.#{index / 250}.#{index % 250}" }.join("\n")
    result = parse(text)
    assert_equal stub_const, result.rows.size
    assert_match "au-delà de", result.refused.last.reason
  end
end
