require "test_helper"

# After an extension sync, only the servers whose extension reasons changed
# get their whole health computed again (Server.refresh_extension_health!).
class ServerExtensionHealthTest < ActiveSupport::TestCase
  include IntegrationHelpers
  include StubHelpers

  def run(...)
    with_integrations { super }
  end

  setup do
    @alerting = []
    stub_method_until_teardown(DemoIntegration, :health_reasons, lambda { |_integration, server|
      @alerting.include?(server.id) ? [ Inventory::HealthStatus.reason("warn", "integrations.demo.health.alert") ] : []
    })
    enable_demo
  end

  test "only the servers whose extension reasons changed are refreshed" do
    web, db = servers(:web), servers(:db)
    [ web, db ].each(&:refresh_health!)
    assert_not web.extension_reasons_changed?

    @alerting = [ web.id, db.id ]
    db.refresh_health!
    assert web.extension_reasons_changed?
    assert_not db.extension_reasons_changed?, "the stored reasons already say it"

    evaluated = []
    evaluate = Inventory::HealthStatus.method(:evaluate)
    stub_method(Inventory::HealthStatus, :evaluate, ->(server, **options) { evaluated << server.name; evaluate.call(server, **options) }) do
      Server.refresh_extension_health!([ web, db ])
    end
    assert_equal [ web.name ], evaluated
    assert_includes web.reload.health_reasons.map { |reason| reason["key"] }, "integrations.demo.health.alert"
    assert_not web.extension_reasons_changed?

    @alerting = []
    assert db.reload.extension_reasons_changed?, "a reason gone"
  end

  test "the reasons of the inventory are not compared" do
    web = servers(:web)
    web.update_columns(health_reasons: [ Inventory::HealthStatus.reason("warn", "disk_full").to_h ])
    assert_not web.extension_reasons_changed?
  end
end
