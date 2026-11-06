require "test_helper"

# The DNS alerts common to every source (phase 14.3).
class Dns::AlertsTest < ActiveSupport::TestCase
  def row(name, value) = { zone: "example.test", name: name, record_type: "A", value: value }

  test "a record outside the fleet is logged once, whatever the source, not on the first run" do
    AppSetting.current.update!(dns_alert_outside: true)
    Dns::Store.replace("ovh", [ row("old.example.test", "198.51.100.9") ])
    assert_equal 0, Activity.of_kind(:dns_record_outside_fleet).count, "first run"

    assert_difference -> { Activity.of_kind(:dns_record_outside_fleet).count }, 1 do
      Dns::Store.replace("ovh", [ row("legacy.example.test", "198.51.100.10"), row("old.example.test", "198.51.100.9") ])
    end
    assert_equal "legacy.example.test pointe vers 198.51.100.10, hors du parc", Activity.of_kind(:dns_record_outside_fleet).sole.summary
    assert_no_difference -> { Activity.of_kind(:dns_record_outside_fleet).count } do
      Dns::Store.replace("ovh", [ row("legacy.example.test", "198.51.100.10") ])
    end
  end

  test "a new source's records are not reported at its first sync, a record known elsewhere is not new" do
    AppSetting.current.update!(dns_alert_outside: true)
    Dns::Store.replace("ovh", [ row("old.example.test", "198.51.100.9") ])
    Dns::Store.replace("ovh", [ row("old.example.test", "198.51.100.9") ])
    assert_no_difference -> { Activity.of_kind(:dns_record_outside_fleet).count }, "Technitium turned on later: its first records are not news" do
      Dns::Store.replace("technitium", [ row("db.lan.test", "10.0.0.12"), row("vpn.lan.test", "10.8.0.100") ])
    end
    assert_difference -> { Activity.of_kind(:dns_record_outside_fleet).count }, 1 do
      Dns::Store.replace("technitium", [ row("db.lan.test", "10.0.0.12"), row("vpn.lan.test", "10.8.0.100"), row("old.example.test", "198.51.100.9"), row("new.lan.test", "10.0.0.99") ])
    end
    assert_equal "new.lan.test pointe vers 10.0.0.99, hors du parc", Activity.of_kind(:dns_record_outside_fleet).sole.summary
  end

  test "the flat state written by the migration counts as known" do
    AppSetting.current.update!(dns_alert_outside: true, dns_alert_state: { "outside" => [ "old.example.test 198.51.100.9" ] })
    DnsRecord.create!(source: "ovh", source_id: "x", zone: "example.test", name: "old.example.test", record_type: "A", value: "198.51.100.9")
    assert_difference -> { Activity.of_kind(:dns_record_outside_fleet).count }, 1 do
      Dns::Store.replace("ovh", [ row("old.example.test", "198.51.100.9"), row("legacy.example.test", "198.51.100.10") ])
    end
  end

  test "a name that differs between sources is logged only when the alert is on" do
    Dns::Store.replace("ovh", [ row("www.example.test", "203.0.113.10") ])
    assert_no_difference -> { Activity.of_kind(:dns_record_conflict).count } do
      Dns::Store.replace("technitium", [ row("www.example.test", "10.8.0.100") ])
    end

    AppSetting.current.update!(dns_alert_conflict: true)
    Dns::Store.replace("technitium", [ row("app.example.test", "10.8.0.101") ])
    assert_difference -> { Activity.of_kind(:dns_record_conflict).count }, 1 do
      Dns::Store.replace("ovh", [ row("www.example.test", "203.0.113.10"), row("app.example.test", "203.0.113.11") ])
    end
    assert_equal "app.example.test diffère entre OVHcloud, Technitium", Activity.of_kind(:dns_record_conflict).sole.summary
  end
end
