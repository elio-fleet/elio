# Counts shown next to the entries of the sidebar. Coloured only when there is
# something to handle (the rule of the design system); cheap queries only,
# since the sidebar is on every page.
class SidebarCounts
  Count = Data.define(:value, :tone)

  def initialize(settings: AppSetting.current)
    @settings = settings
  end

  def servers = Count.new(Server.count, nil)

  # Fixable CVEs of the servers' own packages from the alert severity (what makes a server critical).
  def vulnerabilities
    minimum = @settings.vulnerability_alert_severity
    return if minimum == "none"

    count = ServerVulnerability.host.fixable.at_least(minimum).distinct.count(:cve)
    Count.new(count, :crit) if count.positive?
  end

  def docker
    critical = Server.where(docker_status: "crit").count
    return Count.new(critical, :crit) if critical.positive?

    warning = Server.where(docker_status: "warn").count
    Count.new(warning, :warn) if warning.positive?
  end

  # Servers with a scheduled task (timer) failed or late.
  def scheduled_tasks
    count = Server.where("EXISTS (SELECT 1 FROM jsonb_array_elements(servers.health_reasons) reason WHERE reason->>'key' LIKE 'health.timer%')").count
    Count.new(count, :warn) if count.positive?
  end

  def running_tasks
    count = BackgroundTask.unfinished.count
    Count.new(count, nil) if count.positive?
  end
end
