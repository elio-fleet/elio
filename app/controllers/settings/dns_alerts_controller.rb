# Settings → Extensions → DNS: the alerts common to every DNS source
# (outside the fleet, server without a DNS name, records that differ between
# sources). Administrators.
class Settings::DnsAlertsController < ApplicationController
  require_permission :administer

  def update
    settings = AppSetting.current
    values = params.expect(dns_alerts: [ :outside, :without_name, :conflict, ignored_group_ids: [] ])
    settings.update!(dns_alert_outside: values[:outside] == "1", dns_alert_without_name: values[:without_name] == "1", dns_alert_conflict: values[:conflict] == "1",
                     dns_without_name_ignored_group_ids: Array(values[:ignored_group_ids]).compact_blank.map(&:to_i) & ServerGroup.ids)
    Server.includes(:inventory_snapshots).find_each(&:refresh_health!)
    redirect_to settings_integrations_path(anchor: "dns-alerts"), notice: t("settings.dns_alerts.saved"), status: :see_other
  end
end
