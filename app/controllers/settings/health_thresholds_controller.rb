module Settings
  # Thresholds of the health state (Inventory::HealthStatus), then the health
  # of every server is recomputed with them.
  class HealthThresholdsController < ApplicationController
    require_permission :administer

    FIELDS = %i[health_disk_warn health_disk_crit health_inodes_warn health_inodes_crit health_memory_warn health_memory_crit
                health_swap_warn health_swap_crit health_load_warn health_sustained_minutes].freeze

    def update
      setting = AppSetting.current
      if setting.update(params.expect(app_setting: FIELDS))
        Server.find_each(&:refresh_health!)
        redirect_to settings_path(anchor: "health-thresholds"), notice: t("health_thresholds_controller.saved")
      else
        redirect_to settings_path(anchor: "health-thresholds"), alert: t("health_thresholds_controller.invalid", full_messages_to_sentence: setting.errors.full_messages.to_sentence)
      end
    end
  end
end
