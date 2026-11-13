require "test_helper"

class Integrations::ManualDnsTest < ActiveSupport::TestCase
  setup do
    servers(:web).update!(extra_addresses_text: "203.0.113.10")
    @integration = Integration.find_or_create_by!(kind: "manual_dns").tap { |integration| integration.update!(enabled: true) }
  end

  def source(name, records)
    @integration.connections.build(name: name).tap do |connection|
      connection.assign_form("records" => records)
      connection.save!
    end
  end

  test "the preview reads the CSV without storing anything" do
    connection = @integration.connections.build(name: "Bureau")
    connection.assign_form("records" => "www.example.com,A,203.0.113.10\nmail.example.com,MX,mx")

    assert_equal "1 enregistrement lu, 1 ligne(s) refusée(s)\nLigne 2 refusée (type non pris en charge (A, AAAA ou CNAME)) : mail.example.com,MX,mx",
                 Integrations::ManualDns.test_connection(connection)
    assert_equal 0, DnsRecord.count
  end

  test "each source replaces its own records, attached like any source, logged when they change, shown under its name" do
    office = source("Bureau", "www.example.com,A,203.0.113.10\napp.example.com,CNAME,www.example.com")
    lab = source("Labo", "lab.example.com,A,10.9.9.9")

    assert_equal "2 enregistrements lus, 0 ligne(s) refusée(s)", office.sync!
    lab.sync!
    www = DnsRecord.find_by!(name: "www.example.com")
    assert_equal [ "manual:#{office.id}", servers(:web) ], [ www.source, www.server ]
    assert_equal servers(:web), DnsRecord.find_by!(name: "app.example.com").server
    assert_equal "Bureau", www.source_label
    assert_equal "Source DNS « Bureau » : 2 enregistrements (+2 / −0)", Activity.of_kind(:dns_manual_updated).first.summary
    assert_equal "2 enregistrements · 0 ligne(s) refusée(s)", Integrations::ManualDns.connection_summary(office.reload)

    office.assign_form("records" => "www.example.com,A,203.0.113.10")
    office.save!
    assert_difference -> { Activity.of_kind(:dns_manual_updated).count }, 1 do
      office.sync!
      office.sync!
    end
    assert_equal %w[lab.example.com www.example.com], DnsRecord.order(:name).pluck(:name)
    assert_equal [ "Bureau", "Labo" ], Dns.sources.map(&:label)
  end

  test "deleting a source deletes its records" do
    office = source("Bureau", "www.example.com,A,203.0.113.10")
    office.sync!
    office.destroy!
    assert_equal 0, DnsRecord.count
  end
end
