module Settings
  # Options of the suggested firewall rules: block all the incoming IPv6 in
  # the ufw rules, and the health reason for ports reachable in IPv6 without
  # the OVHcloud network firewall (the health of every server is recomputed
  # when it changes).
  class FirewallOptionsController < ApplicationController
    require_permission :administer

    def update
      setting = AppSetting.current
      setting.update!(params.expect(app_setting: %i[ufw_block_ipv6 ovh_ipv6_health]))
      Server.find_each(&:refresh_health!) if setting.saved_change_to_ovh_ipv6_health?
      redirect_to settings_path(anchor: "firewall-settings"), notice: t("firewall_options_controller.saved")
    end
  end
end
