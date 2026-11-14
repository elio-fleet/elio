require "test_helper"

# AUDIT.md S21: a compromised server controls what its commands print (unit
# names, processes, host name…). Whatever it sends is shown as text, never
# interpreted as HTML, in the pages and the activity log.
class HostileServerOutputTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PAYLOAD = %(<img src=x onerror="alert(1)"><script>alert(2)</script>)

  test "inventory data and activities from a server are escaped" do
    server = servers(:web)
    server.inventory_snapshots.create!(category: "services", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                       data: { "units" => [ { "name" => "#{PAYLOAD}.service", "load" => "loaded", "active" => "failed", "sub" => "failed",
                                                              "description" => PAYLOAD } ], "containers" => [], "docker" => "absent" })
    server.inventory_snapshots.create!(category: "os", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                       data: { "hostname" => PAYLOAD, "name" => PAYLOAD })
    Activity.record!(:service_failed, server: server, service: PAYLOAD)
    sign_in users(:one)

    [ server_path(server, tab: "services"), server_path(server, tab: "overview"), activities_path, servers_path ].each do |path|
      get path
      assert_response :success
      assert_not_includes response.body, PAYLOAD, path
      assert_not_includes response.body, "<script>alert(2)", path
      assert_includes response.body, "&lt;script&gt;alert(2)&lt;/script&gt;", path
    end
  end
end
