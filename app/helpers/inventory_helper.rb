# Formatting of the inventory data (see Inventory::Collectors).
module InventoryHelper
  def virtualization_label(value) = t("inventory_helper.virtualization.#{value.presence || "unknown"}", default: value.to_s.capitalize.presence || t("inventory_helper.virtualization.unknown"))

  def privilege_label(value) = t("inventory_helper.privilege.#{value.presence || "unknown"}", default: t("inventory_helper.privilege.unknown"))

  # 31,3 Go
  def human_bytes(bytes) = bytes ? number_to_human_size(bytes, precision: 3, significant: true) : "—"

  # End of support of the server's system: a warning when it is near or past,
  # a discreet date otherwise, nothing when the release is unknown.
  def end_of_life_badge(os_id, version_id)
    status = Inventory::EndOfLife.status(os_id, version_id)
    return unless status.known?

    date = l(status.date, format: :long)
    case status.state
    when :ended then status_badge(:crit, t("inventory_helper.end_of_life.ended", date: date), class: "end-of-life")
    when :soon then status_badge(:warn, t("inventory_helper.end_of_life.soon", date: date), class: "end-of-life")
    else tag.span(t("inventory_helper.end_of_life.supported", date: date), class: "end-of-life text-xs text-ink-3")
    end
  end

  # A listen address of ss, with what it means when it is not a plain IP:
  # "0.0.0.0 every IPv4 interface", "127.0.0.1 this machine only".
  def listen_address(address)
    meaning = case address.to_s
    when "0.0.0.0" then "all_ipv4"
    when "::" then "all_ipv6"
    when "*", "" then "all"
    else "loopback" if Inventory::IpScope.of(address) == "local"
    end
    hint = tag.span(t("inventory_helper.listen_address.#{meaning}"), class: "font-sans text-ink-3") if meaning
    tag.span(safe_join([ tag.span(address.presence || "*", class: "font-mono"), hint ].compact, " "), class: "listen-address block")
  end

  def period_label(period) = t("inventory_helper.periods.#{period}", default: period.to_s)

  # Readable schedules of a timer ("OnCalendar=*-*-* 06:00:00" → "every day at 6:00").
  def timer_schedule_text(timer)
    Array(timer["schedules"]).map { |schedule| Inventory::CronSchedule.timer(schedule).text }.join(" · ").presence || "—"
  end

  def cron_schedule_text(task) = Inventory::CronSchedule.cron(task["schedule"]).text

  # State of a systemd timer: failed, late, inactive or ok.
  def timer_state_badge(timer)
    if timer["failed"] then status_badge(:crit, t("inventory_helper.timer.failed"), title: t("inventory_helper.timer.last_run", result: timer["result"], code: timer["exit_status"]), class: "timer-state")
    elsif timer["late"] then status_badge(:warn, t("inventory_helper.timer.late"), class: "timer-state")
    elsif timer["active"] != "active" then status_badge(:neutral, t("inventory_helper.timer.inactive"), class: "timer-state")
    else status_badge(:good, t("inventory_helper.timer.ok"), class: "timer-state")
    end
  end

  def timer_time(value) = value ? relative_time_tag(Time.zone.parse(value)) : tag.span("—", class: "text-ink-3")

  # State of a Docker container: what goes wrong first.
  def container_state_badge(container)
    if container["looping"] then status_badge(:crit, t("inventory_helper.container.looping"), class: "container-state")
    elsif container["health"] == "unhealthy" then status_badge(:crit, t("inventory_helper.container.unhealthy"), class: "container-state")
    elsif container["state"] == "running" then status_badge(:good, container["health"] == "starting" ? t("inventory_helper.container.starting") : t("inventory_helper.container.running"), class: "container-state")
    elsif container["state"] == "exited" then status_badge(:neutral, container["exit_code"].to_i.zero? ? t("inventory_helper.container.stopped") : t("inventory_helper.container.stopped_code", code: container["exit_code"]), class: "container-state")
    else status_badge(:warn, container["state"], class: "container-state")
    end
  end

  # Privileged container or Docker socket mounted: whoever controls the
  # container is root on the host.
  def container_risk_badges(container)
    badges = %w[privileged docker_socket].select { |key| container[key] }.map do |key|
      status_badge(:warn, t("inventory_helper.container.#{key}"), class: "container-risk ml-1", title: t("inventory_helper.container.#{key}_hint"))
    end
    safe_join(badges)
  end

  # Published ports with their exposure: every interface, the machine only,
  # or one address.
  def container_ports(container)
    ports = Array(container["ports"])
    return if ports.empty?

    items = ports.map do |port|
      address = port["address"].include?(":") ? "[#{port["address"]}]" : port["address"]
      tag.span(title: t("inventory_helper.container.exposure.#{port["exposure"]}_hint")) do
        safe_join([ "#{address}:#{port["port"]}→#{port["target"]} ", tag.span(t("inventory_helper.container.exposure.#{port["exposure"]}"), class: ("text-ink-2" if port["exposure"] == "all")) ])
      end
    end
    tag.span(safe_join(items, ", "), class: "container-ports block max-w-xs truncate font-mono text-[11px] text-ink-3")
  end

  # Networks and mounts (volume or host path → path in the container).
  def container_attachments(container)
    mounts = Array(container["mounts"]).map { |mount| "#{mount["source"] || mount["type"]}:#{mount["destination"]}#{":ro" if mount["read_only"]}" }
    parts = [ (t("inventory_helper.container.networks", list: container["networks"].join(", ")) if container["networks"].present?),
              (t("inventory_helper.container.mounts", list: mounts.join(", ")) if mounts.any?) ].compact
    return if parts.empty?

    text = parts.join(" · ")
    tag.span(text, class: "container-attachments block max-w-xs truncate text-[11px] text-ink-3", title: text)
  end

  # `update` (ImageUpdate): names the newer fix of a pinned version, and the last version of its major below.
  def image_update_badge(state, update = nil)
    major = (tag.span(t("inventory_helper.image_update.in_major", major: update.latest_in_major[/\d+/], version: update.latest_in_major), class: "image-update-major block text-[11px] text-ink-3") if update&.latest_in_major.present?)
    badge = case state
    when :available then status_badge(:warn, update&.latest_patch.present? ? t("inventory_helper.image_update.newer", version: update.latest_patch) : t("inventory_helper.image_update.available"), class: "image-update")
    when :current then tag.span(t("inventory_helper.image_update.current"), class: "image-update text-xs text-ink-3")
    else tag.span("—", class: "image-update text-xs text-ink-3", title: t("inventory_helper.image_update.unknown"))
    end
    safe_join([ badge, major ].compact)
  end

  def scan_label(scanner) = t("inventory_helper.scanners.#{scanner.presence || "none"}", default: scanner.to_s)

  # Classes of each score colour (written in full for Tailwind).
  SCORE_PILL_CLASSES = {
    "green" => "bg-good-soft text-good-ink ring-good/40", "orange" => "bg-warn-soft text-warn-ink ring-warn/40",
    "red" => "bg-crit-soft text-crit-ink ring-crit/40", "violet" => "bg-accent-soft text-accent ring-accent/40",
    "blue" => "bg-sky-100 text-sky-800 ring-sky-400/50 dark:bg-sky-950 dark:text-sky-200", "gray" => "bg-subtle text-ink-2 ring-line"
  }.freeze

  # A CVSS score in a rounded rectangle of the colour of its band
  # (Settings → Vulnerabilities); a dash without a score.
  def score_pill(score, size: :small, **options)
    sizes = { small: "min-w-9 px-1.5 py-0.5 text-xs", medium: "min-w-12 px-2 py-1 text-sm", large: "min-w-16 px-3 py-1.5 text-2xl" }
    color = score && app_settings.score_color(score)
    classes = [ "score-pill inline-flex items-center justify-center rounded-md font-semibold tabular-nums ring-1 ring-inset", sizes.fetch(size),
                SCORE_PILL_CLASSES.fetch(color, SCORE_PILL_CLASSES["gray"]), options.delete(:class) ]
    tag.span(score ? number_with_precision(score, precision: 1) : "—", class: classes.compact.join(" "), data: { color: color }, **options)
  end

  # Average CVSS score of a CVE ("8.6"), with the exploitation badges.
  def cve_score(rating, compact: false)
    return tag.span("—", class: "cve-score text-xs text-ink-3", title: t("inventory_helper.score.none")) unless rating&.score || rating&.exploited || rating&.epss

    parts = []
    parts << score_pill(rating.score, title: t("inventory_helper.score.average", providers: t("count.providers", count: rating.scores_count))) if rating.score
    parts << status_badge(:crit, t("inventory_helper.score.exploited"), class: "cve-exploited",
                                 title: rating.exploited_since ? t("inventory_helper.score.kev_since", date: l(rating.exploited_since, format: :long)) : t("inventory_helper.score.kev")) if rating.exploited
    if rating.epss && rating.epss >= 0.01 && !compact
      parts << tag.span("EPSS #{epss_percentage(rating.epss)}", class: "text-[11px] text-ink-3", title: t("inventory_helper.score.epss"))
    end
    tag.span(safe_join(parts, " "), class: "cve-score inline-flex flex-wrap items-center gap-1.5 text-xs")
  end

  # "12%", "99.5%" (never rounded up to 100%).
  def epss_percentage(value)
    percent = (value.to_f * 100).floor(1)
    number_to_percentage(percent, precision: 1, strip_insignificant_zeros: true)
  end

  # CVSS 3 and 4 metrics and their values, explained (inventory_helper.cvss.*):
  # VC/VI/VA (CVSS 4) read like C/I/A.
  CVSS_METRICS = {
    "AV" => %w[N A L P], "AC" => %w[L H], "AT" => %w[N P], "PR" => %w[N L H], "UI" => %w[N R P A], "S" => %w[U C],
    "C" => %w[H L N], "VC" => %w[H L N], "I" => %w[H L N], "VI" => %w[H L N], "A" => %w[H L N], "VA" => %w[H L N]
  }.freeze

  # "CVSS:3.1/AV:N/AC:H/…" → [["Vector", "network"], ["Complexity", "high"], …] (CVSS 3 and 4).
  def cvss_vector_parts(vector)
    vector.to_s.split("/").filter_map do |part|
      key, value = part.split(":")
      next unless CVSS_METRICS.key?(key)

      values = key.sub(/\AV(?=[CIA]\z)/, "")
      [ t("inventory_helper.cvss.#{key}"), CVSS_METRICS[key].include?(value) ? t("inventory_helper.cvss_values.#{values}.#{value}") : value ]
    end
  end

  SEVERITY_TONES = { "critical" => :crit, "high" => :crit, "medium" => :warn, "low" => :neutral, "unknown" => :neutral }.freeze

  # Name of a Docker image for a line of text: an image without tag is known by
  # its digest, shortened like the docker CLI does ("sha256:" + 12 characters).
  def image_label(image)
    image.to_s.start_with?("sha256:") ? image.to_s.first(19) : image.to_s
  end

  def severity_badge(severity)
    status_badge(SEVERITY_TONES.fetch(severity.to_s, :neutral), Vulnerability.severity_label(severity), class: "severity", data: { severity: severity })
  end

  # Why Debian leaves a CVE without a fix (no_dsa, postponed, ignored), explained on hover; nil for any other.
  def distro_status_badge(status)
    return unless Vulnerability::DISTRO_STATUSES.key?(status.to_s)

    status_badge(:neutral, Vulnerability.distro_status_label(status), title: Vulnerability.distro_status_label(status, :help), class: "distro-status font-sans",
                                                                      data: { distro_status: status })
  end

  # Badge of an inventory snapshot that is not plainly ok.
  def inventory_status_badge(snapshot)
    case snapshot&.status
    when "error" then status_badge(:crit, t("inventory_helper.snapshot.error"), title: snapshot.message, class: "inventory-status")
    when "partial" then status_badge(:warn, t("inventory_helper.snapshot.partial"), title: snapshot.message, class: "inventory-status")
    when "unsupported" then status_badge(:neutral, t("inventory_helper.snapshot.unsupported"), title: snapshot.message, class: "inventory-status")
    end
  end

  def network_kind_label(kind) = t("inventory.network_kinds.#{kind}", default: kind.to_s.capitalize)

  def vpn_interface?(kind) = Inventory::Collectors::Network::VPN_KINDS.include?(kind)

  # What the interface is, for people: "VPN" for every VPN kind (WireGuard,
  # tun / tap, IP tunnels; the exact kind in network_kind_label), else its kind.
  def interface_kind_label(kind) = vpn_interface?(kind) ? t("inventory_helper.vpn") : network_kind_label(kind)

  # Reach of an address, as an icon (narrow column): a globe for public, a
  # lock for private (LAN, VPN), a server for local. The word in a title and
  # for screen readers.
  SCOPE_ICONS = { "public" => [ :globe, "text-warn-ink" ], "private" => [ :lock_closed, "text-ink-3" ], "local" => [ :server_stack, "text-ink-3" ] }.freeze

  def address_scope_icon(scope)
    scope = SCOPE_ICONS.key?(scope) ? scope : "local"
    name, color = SCOPE_ICONS.fetch(scope)
    label = t("inventory_helper.scope.#{scope}")
    tag.span(class: "address-scope inline-flex #{color}", title: t("inventory_helper.scope_hint.#{scope}"), data: { scope: scope }) do
      safe_join([ icon(name, class: "h-4 w-4"), tag.span(label, class: "sr-only") ])
    end
  end

  # "Debian GNU/Linux 12 (bookworm)" → "Debian 12", for dense lists (full name in a title).
  def short_os_name(name) = name.to_s.sub("GNU/Linux ", "").sub(/\s*\([^)]*\)\z/, "").squish
end
