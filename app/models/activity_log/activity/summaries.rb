# One-line description of each kind of activity, in the reader's language
# (activity.summaries.*), run in the context of the Activity (data,
# server_name, target, key_name…). Every kind of Activity::KINDS has one
# (see activity_test.rb). Values stored in `data` stay in the language they
# were recorded in.
module Activity::Summaries
  def self.t(key, **options) = I18n.t("activity.summaries.#{key}", **options)

  # " (a, b)" or "".
  # " (623a4be « fix: export »)", " (623a4be)" or "".
  def self.coolify_commit(data)
    parts = [ data["commit"], (I18n.t("activity.summaries.quoted", text: data["message"]) if data["message"].present?) ].compact
    parts.any? ? " (#{parts.join(" ")})" : ""
  end

  def self.list(values) = Array(values).any? ? " (#{Array(values).join(", ")})" : ""

  BY_KIND = {
    key_added: proc do
      key = data["duration_label"] ? :key_added_for : :key_added
      Activity::Summaries.t(key, name: public_key_name, target: target, duration: data["duration_label"])
    end,
    key_removed: proc { Activity::Summaries.t(:key_removed, name: key_name, target: target) },
    key_expired: proc { Activity::Summaries.t(:key_expired, name: public_key_name || key_name, target: target) },
    unknown_key_detected: proc { Activity::Summaries.t(:unknown_key_detected, name: key_name, target: target) },
    key_disappeared: proc { Activity::Summaries.t(:key_disappeared, name: key_name, target: target) },
    ssh_access_lost: proc { Activity::Summaries.t(:ssh_access_lost, server: server_name) },
    host_key_changed: proc { Activity::Summaries.t(:host_key_changed, server: server_name, fingerprint: data["new_fingerprint"]) },
    server_unreachable: proc { Activity::Summaries.t(:server_unreachable, server: server_name) },
    server_back_online: proc { Activity::Summaries.t(:server_back_online, server: server_name) },
    os_upgraded: proc { Activity::Summaries.t(:os_upgraded, server: server_name, from: data["from"], to: data["to"]) },
    server_rebooted: proc { Activity::Summaries.t(:server_rebooted, server: server_name) },
    health_warning: proc { Activity::Summaries.t(:health_warning, server: server_name, reasons: Array(data["reasons"]).map { |reason| Inventory::HealthStatus.text(reason) }.join(", ")) },
    health_critical: proc { Activity::Summaries.t(:health_critical, server: server_name, reasons: Array(data["reasons"]).map { |reason| Inventory::HealthStatus.text(reason) }.join(", ")) },
    health_recovered: proc { Activity::Summaries.t(:health_recovered, server: server_name) },
    docker_warning: proc { Activity::Summaries.t(:docker_warning, server: server_name, reasons: Array(data["reasons"]).map { |reason| Inventory::HealthStatus.text(reason) }.join(", ")) },
    docker_critical: proc { Activity::Summaries.t(:docker_critical, server: server_name, reasons: Array(data["reasons"]).map { |reason| Inventory::HealthStatus.text(reason) }.join(", ")) },
    docker_recovered: proc { Activity::Summaries.t(:docker_recovered, server: server_name) },
    packages_changed: proc do
      counts = %w[installed upgraded removed].filter_map { |key| Activity::Summaries.t("packages.#{key}", count: data[key].to_i) if data[key].to_i.positive? }
      Activity::Summaries.t(:packages_changed, server: server_name, counts: counts.join(", ")) + Activity::Summaries.list(data["examples"])
    end,
    service_failed: proc { Activity::Summaries.t(:service_failed, service: data["service"], server: server_name) },
    service_recovered: proc { Activity::Summaries.t(:service_recovered, service: data["service"], server: server_name) },
    container_stopped: proc { Activity::Summaries.t(:container_stopped, container: data["container"], server: server_name) },
    container_started: proc { Activity::Summaries.t(:container_started, container: data["container"], server: server_name) },
    scheduled_task_failed: proc { Activity::Summaries.t(:scheduled_task_failed, task: data["task"], server: server_name) },
    scheduled_task_late: proc { Activity::Summaries.t(:scheduled_task_late, task: data["task"], server: server_name) },
    vulnerability_found: proc do
      where = data["image"] ? Activity::Summaries.t(:in_image, image: data["image"], server: server_name) : target
      Activity::Summaries.t(:vulnerability_found, count: data["count"].to_i, where: where, cves: Array(data["cves"]).join(", ")) + Activity::Summaries.list(data["packages"])
    end,
    vulnerability_feed_failed: proc { Activity::Summaries.t(:vulnerability_feed_failed, feed: data["feed"], error: data["error"]) },
    container_unhealthy: proc { Activity::Summaries.t(:container_unhealthy, container: data["container"], server: server_name) },
    container_restarting: proc { Activity::Summaries.t(:container_restarting, container: data["container"], server: server_name) },
    image_update_available: proc { Activity::Summaries.t(:image_update_available, image: data["image"], server: server_name) },
    port_opened: proc { Activity::Summaries.t(:port_opened, port: data["port"], server: server_name) + (data["process"] ? " (#{data["process"]})" : "") },
    port_closed: proc { Activity::Summaries.t(:port_closed, port: data["port"], server: server_name) },
    ip_address_added: proc { Activity::Summaries.t(:ip_address_added, address: data["address"], server: server_name) },
    ip_address_removed: proc { Activity::Summaries.t(:ip_address_removed, address: data["address"], server: server_name) },
    security_updates_available: proc { Activity::Summaries.t(:security_updates_available, count: data["count"].to_i, server: server_name) },
    server_created: proc { Activity::Summaries.t(:server_created, server: server_name) },
    server_note_added: proc { Activity::Summaries.t(:server_note_added, server: server_name, author: author_name, excerpt: data["excerpt"]) },
    server_updated: proc { Activity::Summaries.t(:server_updated, server: server_name) },
    servers_imported: proc do
      names = data["names"].to_a
      more = data["count"].to_i > names.size ? "…" : ""
      Activity::Summaries.t(:servers_imported, count: data["count"].to_i, source: data["format"], names: "#{names.join(", ")}#{more}")
    end,
    server_deleted: proc { Activity::Summaries.t(:server_deleted, server: server_name) },
    server_group_created: proc { Activity::Summaries.t(:server_group_created, group: data["group_name"], count: data["servers"].to_i) },
    server_group_deleted: proc { Activity::Summaries.t(:server_group_deleted, group: data["group_name"]) },
    user_invited: proc { Activity::Summaries.t(:user_invited, email: data["email"], role: data["role_label"]) },
    invitation_accepted: proc { Activity::Summaries.t(:invitation_accepted, email: data["email"], role: data["role_label"]) },
    invitation_revoked: proc { Activity::Summaries.t(:invitation_revoked, email: data["email"]) },
    user_role_changed: proc { Activity::Summaries.t(:user_role_changed, email: data["email"], from: data["from"], to: data["to"]) },
    user_deactivated: proc { Activity::Summaries.t(:user_deactivated, email: data["email"]) },
    user_reactivated: proc { Activity::Summaries.t(:user_reactivated, email: data["email"]) },
    user_locked: proc { Activity::Summaries.t(:user_locked, email: data["email"], count: data["attempts"].to_i) },
    two_factor_enabled: proc { Activity::Summaries.t(:two_factor_enabled, email: data["email"]) },
    two_factor_disabled: proc { data["reset_by"] ? Activity::Summaries.t(:two_factor_reset, email: data["email"], by: data["reset_by"]) : Activity::Summaries.t(:two_factor_disabled, email: data["email"]) },
    two_factor_backup_code_used: proc { Activity::Summaries.t(:two_factor_backup_code_used, email: data["email"], count: data["left"].to_i) },
    public_key_created: proc { Activity::Summaries.t(:public_key_created, name: public_key_name) },
    public_key_deleted: proc { Activity::Summaries.t(:public_key_deleted, name: public_key_name) },
    ssh_key_generated: proc { Activity::Summaries.t(data["regenerated"] ? :ssh_key_regenerated : :ssh_key_generated) },
    ssh_key_rotation_started: proc { Activity::Summaries.t(:ssh_key_rotation_started, count: data["servers"].to_i) },
    ssh_key_rotated: proc do
      forced = data["forced"] ? " #{Activity::Summaries.t(:rotation_forced, count: data["failed"].to_i)}" : ""
      Activity::Summaries.t(:ssh_key_rotated, count: data["servers"].to_i) + forced
    end,
    automation_run: proc { Activity::Summaries.t(:automation_run, automation: data["automation"] ? Automation.label_for(data["automation"]) : data["automation_label"], result: data["result"]) },
    monitor_down: proc { Activity::Summaries.t(:monitor_down, monitor: data["monitor"]) + (server_name ? " (#{server_name})" : "") },
    monitor_up: proc { Activity::Summaries.t(:monitor_up, monitor: data["monitor"]) + (server_name ? " (#{server_name})" : "") },
    monitor_cert_expiring: proc { Activity::Summaries.t(:monitor_cert_expiring, monitor: data["monitor"], count: data["days"].to_i) },
    server_without_monitor: proc { Activity::Summaries.t(:server_without_monitor, server: server_name) },
    ovh_service_expiring: proc { Activity::Summaries.t(:ovh_service_expiring, service: data["service"], count: data["days"].to_i) },
    gandi_domain_expiring: proc { Activity::Summaries.t(:gandi_domain_expiring, domain: data["domain"], count: data["days"].to_i) },
    dns_record_outside_fleet: proc { Activity::Summaries.t(:dns_record_outside_fleet, record: data["record"], target: data["target"]) },
    dns_record_conflict: proc { Activity::Summaries.t(:dns_record_conflict, record: data["record"], sources: Array(data["sources"]).join(", ")) },
    ovh_service_unmanaged: proc { Activity::Summaries.t(:ovh_service_unmanaged, kind: data["kind_label"], service: data["service"]) },
    integration_enabled: proc { Activity::Summaries.t(:integration_enabled, integration: data["integration_label"]) },
    integration_disabled: proc { Activity::Summaries.t(:integration_disabled, integration: data["integration_label"]) },
    integration_sync_failed: proc { Activity::Summaries.t(:integration_sync_failed, integration: data["integration_label"], error: data["error"]) },
    coolify_deployed: proc { Activity::Summaries.t(:coolify_deployed, application: data["application"], commit: Activity::Summaries.coolify_commit(data)) },
    coolify_deploy_failed: proc { Activity::Summaries.t(:coolify_deploy_failed, application: data["application"], commit: Activity::Summaries.coolify_commit(data)) },
    coolify_backup_failed: proc { Activity::Summaries.t(:coolify_backup_failed, database: data["database"], team: data["team"]) },
    integration_connection_added: proc { Activity::Summaries.t(:integration_connection_added, integration: data["integration_label"], connection: data["connection"]) },
    integration_connection_removed: proc { Activity::Summaries.t(:integration_connection_removed, integration: data["integration_label"], connection: data["connection"]) }
  }.freeze
end
