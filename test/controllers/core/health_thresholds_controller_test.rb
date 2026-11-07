require "test_helper"

class HealthThresholdsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def params(**overrides)
    { app_setting: { health_disk_warn: 70, health_disk_crit: 85, health_memory_warn: 90, health_memory_crit: 95, health_load_warn: "1.5" }.merge(overrides) }
  end

  test "the general settings show the thresholds form" do
    sign_in users(:one)
    get settings_path
    assert_select "form[action=?] #health-thresholds", settings_path do
      assert_select "input[name='app_setting[health_disk_warn]'][value='80']"
      assert_select "input[name='app_setting[health_load_warn]'][value='2.0']"
    end
  end

  test "saves the thresholds and recomputes the health of the servers" do
    servers(:web).update_columns(ssh_ok: true)
    servers(:web).inventory_snapshots.create!(category: "health", status: "ok", data: { "disks" => [ { "mount" => "/", "used_percent" => 75 } ] },
                                              collected_at: Time.current, checked_at: Time.current)
    servers(:web).refresh_health!
    assert_equal "ok", servers(:web).health_status
    sign_in users(:one)

    patch settings_health_thresholds_path, params: params

    assert_redirected_to settings_path(anchor: "health-thresholds")
    assert_equal "Seuils de santé enregistrés.", flash[:notice]
    assert_equal [ 70, 85, 1.5 ], AppSetting.current.attributes.values_at("health_disk_warn", "health_disk_crit", "health_load_warn").map { |v| v.is_a?(BigDecimal) ? v.to_f : v }
    assert_equal [ "warn", [ "Disque / à 75\u00A0%" ] ], [ servers(:web).reload.health_status, servers(:web).health_reason_texts ]
  end

  test "refuses inconsistent thresholds" do
    sign_in users(:one)

    patch settings_health_thresholds_path, params: params(health_disk_warn: 95)

    assert_match "Seuils invalides", flash[:alert]
    assert_equal 80, AppSetting.current.health_disk_warn
  end

  test "admins only" do
    sign_in users(:operator)
    patch settings_health_thresholds_path, params: params
    assert_response :forbidden
  end
end
