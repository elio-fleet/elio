# Display of what the Coolify extension reads (CoolifyResource): state,
# kind, deployed version, domains, and the resource behind a container.
module CoolifyHelper
  # running:healthy → good "Running · healthy"; running without a health check → neutral; unhealthy / restarting → warn; exited → crit.
  def coolify_state_badge(resource)
    key = coolify_state_key(resource)
    tone = { "healthy" => :good, "running" => :neutral, "unhealthy" => :warn, "restarting" => :warn, "stopped" => :crit }.fetch(key, :neutral)
    status_badge(tone, t("coolify_helper.states.#{key}"), class: "coolify-state", data: { state: key }, title: resource.status)
  end

  def coolify_state_key(resource)
    if resource.stopped? then "stopped"
    elsif resource.unhealthy? then "unhealthy"
    elsif resource.state == "restarting" then "restarting"
    elsif resource.running? && resource.health == "healthy" then "healthy"
    elsif resource.running? then "running"
    else "other"
    end
  end

  # "Application · Dockerfile", "Service", "Database · PostgreSQL"
  def coolify_kind_detail(resource)
    detail = case resource.kind
    when "application" then t("coolify_helper.build_packs.#{resource.data["build_pack"]}", default: resource.data["build_pack"].to_s.capitalize.presence)
    when "database" then t("coolify_helper.engines.#{resource.data["engine"]}", default: resource.data["engine"].to_s.capitalize.presence)
    end
    [ resource.kind_label, detail ].compact_blank.join(" · ")
  end

  # What runs: "main @ 623a4be" for an application built from git ("main" when Coolify only says HEAD), else the image(s).
  def coolify_version(resource)
    data = resource.data
    if data["git_branch"]
      commit = data["git_commit"].to_s.first(7)
      return commit.in?([ "", "HEAD" ]) ? data["git_branch"] : "#{data["git_branch"]} @ #{commit}"
    end

    (Array(data["images"]).first || data["image"]).presence
  end

  # The application's page in its Coolify instance, or nil.
  def coolify_url(resource)
    path = resource.data["coolify_path"] or return
    base = resource.connection.value(:url).to_s.chomp("/")
    "#{base}#{path}" if Integration.http_url?(base) && path.match?(%r{\A/[\w/-]+\z})
  end

  # "il y a 5 h" + a "failed" badge, for the last deployment of an application.
  def coolify_last_deploy(resource)
    deployment = resource.last_deployment or return tag.span("—", class: "text-ink-3")

    at = deployment["finished_at"] || deployment["at"]
    safe_join([ (relative_time_tag(Time.zone.parse(at)) if at),
                (status_badge(:crit, t("integrations.coolify.server_tab.deploy_failed"), class: "ml-1 deploy-failed") if deployment["status"] == "failed") ].compact)
  end

  def coolify_domain_links(resource, limit: 2)
    domains = resource.domains
    return tag.span(t("coolify_helper.no_domain"), class: "text-ink-3") if domains.empty?

    links = domains.first(limit).map { |domain| link_to(domain, "https://#{domain}", class: "text-accent hover:underline", target: "_blank", rel: "noopener") }
    links << tag.span("+#{domains.size - limit}", class: "text-ink-3", title: domains.drop(limit).join(", ")) if domains.size > limit
    safe_join(links, ", ")
  end

  # "n8n › postgresql": the part of a resource made of several containers (its Compose service, or for a
  # Coolify service the start of the name, "<part>-<service uuid>"), else the resource's name.
  def coolify_container_label(resource, container)
    name = container["name"].to_s
    part = container["service"].presence
    part ||= name.delete_suffix("-#{resource.uuid}") if resource.kind == "service" && name.end_with?("-#{resource.uuid}")
    part.present? && part != resource.name ? "#{resource.name} › #{part}" : resource.name
  end

  # For the Docker card: container → its Coolify resource. Coolify names a
  # container after the resource's uuid ("<uuid>-20261108T120000", "<uuid>",
  # "<service>-<uuid>"), or uses it as the Compose project.
  def coolify_resource_finder(server)
    resources = server.coolify_resources.resources.to_a
    return ->(_container) { nil } if resources.empty?

    ->(container) { resources.find { |resource| [ container["name"], container["project"] ].compact.any? { |value| value.include?(resource.uuid) } } }
  end
end
