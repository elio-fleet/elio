# Options of the suggested firewall rules (Settings → General): block all the
# incoming IPv6 in the ufw rules; a health reason when ports of a server are
# reachable in IPv6 without going through the OVHcloud network firewall
# (it filters only IPv4). health_version: version of the health reasons the
# servers were last computed with (Inventory::HealthStatus::VERSION).
class AddFirewallOptionsToAppSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :app_settings, :ufw_block_ipv6, :boolean, null: false, default: false
    add_column :app_settings, :ovh_ipv6_health, :boolean, null: false, default: false
    add_column :app_settings, :health_version, :integer, null: false, default: 0
  end
end
