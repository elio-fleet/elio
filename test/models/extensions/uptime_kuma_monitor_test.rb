require "test_helper"

class UptimeKumaMonitorTest < ActiveSupport::TestCase
  test "for_host finds the probe by its host name or the host of its URL, never for a blank host" do
    by_url = UptimeKumaMonitor.new(name: "API", url: "https://API.example.com/up")
    by_hostname = UptimeKumaMonitor.new(name: "DB", hostname: "db.example.com")
    broken = UptimeKumaMonitor.new(name: "Broken", url: "https://exa mple.com")
    monitors = [ broken, by_url, by_hostname ]

    assert_equal by_url, UptimeKumaMonitor.for_host(monitors, "api.example.com")
    assert_equal by_hostname, UptimeKumaMonitor.for_host(monitors, "db.example.com")
    assert_nil UptimeKumaMonitor.for_host(monitors, "other.example.com")
    assert_nil UptimeKumaMonitor.for_host(monitors, nil)
    assert_nil UptimeKumaMonitor.for_host([ UptimeKumaMonitor.new(name: "Ping") ], ""), "a probe without target never matches"
  end
end
