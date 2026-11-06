module ApplicationHelper
  # Settings of the instance, read once per page.
  def app_settings = @app_settings ||= AppSetting.current

  # [name, id] of every server, for the "attach to" menus of long lists (read once per page).
  def server_options = @server_options ||= Server.order(:name).pluck(:name, :id)

  # Form options of the ping buttons of the fleet: the badge(s) show
  # "Vérification…" while the request runs (server_ping_controller.js).
  def server_ping_form(badge_id = nil)
    { data: { controller: "quiet-submit", action: "turbo:submit-start->server-ping#start turbo:submit-end->server-ping#finish", server_ping_badge_param: badge_id }.compact }
  end

  # Status filters as pills (activity, tasks, keyring, probes…).
  def filter_pill(label, path, active:, count: nil, **options)
    classes = "rounded-full px-3 py-1 text-sm font-medium ring-1 ring-inset #{active ? "bg-accent-fill text-white ring-accent-fill" : "bg-surface text-ink-2 ring-line hover:bg-subtle"}"
    link_to path, class: classes, aria: { current: (active ? "page" : nil) }, **options do
      safe_join([ label, (tag.span(" #{count}", class: "tabular-nums opacity-70") if count) ].compact)
    end
  end
  # Relative time, e.g. "3 minutes ago", "in 2 hours", "just now".
  # Mirrored by app/javascript/controllers/relative_time_controller.js, with
  # the same texts (js.relative_time): keep both in sync.
  def relative_time_in_words(time, now: Time.current)
    seconds = (time - now).round
    return t(seconds.positive? ? "js.relative_time.within_a_minute" : "js.relative_time.just_now") if seconds.abs < 60

    minutes = (seconds.abs / 60.0).round
    hours = (minutes / 60.0).round
    words = if minutes < 60 then t("js.relative_time.minutes", count: minutes)
    elsif hours < 24 then t("js.relative_time.hours", count: hours)
    else t("js.relative_time.days", count: (hours / 24.0).round)
    end

    t(seconds.positive? ? "js.relative_time.from_now" : "js.relative_time.ago", time: words)
  end

  # <time> showing `prefix` + the relative time, kept up to date in the browser,
  # with the exact date as tooltip. Once `time` has passed, shows `expired` if given.
  def relative_time_tag(time, prefix: "", expired: nil, **options)
    text = expired && time <= Time.current ? expired : "#{prefix}#{relative_time_in_words(time)}"

    tag.time text, datetime: time.iso8601, title: l(time, format: :long),
                   data: { controller: "relative-time", relative_time_datetime_value: time.iso8601,
                           relative_time_prefix_value: prefix, relative_time_expired_value: expired }.compact,
                   **options
  end

  # "0 ligne", "1 ligne", "2 lignes": in French, 0 and 1 are singular
  # (Rails' pluralize only treats 1 as singular).
  def pluralize_fr(count, singular, plural)
    "#{count} #{count.to_i.abs < 2 ? singular : plural}"
  end

  # Shell command adding the app's public key to ~/.ssh/authorized_keys.
  def ssh_key_install_command(ssh_key)
    "mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '#{ssh_key.public_key}' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
  end

  # Tabs of a server page (but the overview) and their labels, for ⌘K.
  def server_tab_labels = (ServersController::TABS - [ "overview" ]).index_with { |tab| t("servers.tabs.#{tab}") }

  # Entries of the ⌘K quick search: pages, groups, servers (`server: true`:
  # the browser derives their tabs from server_tab_labels once something is
  # typed, so a big fleet does not weigh on every page) and keyring keys.
  def command_palette_items
    hint = ->(key) { t("command_palette.hints.#{key}") }
    pages = [
      { label: t("nav.overview"), url: root_path }, { label: t("nav.fleet"), hint: hint.(:fleet), url: servers_path },
      { label: t("nav.packages"), hint: hint.(:packages), url: packages_path }, { label: t("nav.ports"), hint: hint.(:ports), url: ports_path },
      { label: t("nav.scheduled_tasks"), hint: hint.(:scheduled_tasks), url: scheduled_tasks_path }, { label: t("nav.vulnerabilities"), hint: hint.(:vulnerabilities), url: vulnerabilities_path },
      { label: t("nav.docker"), hint: hint.(:docker), url: docker_path }, { label: t("nav.keyring"), hint: hint.(:keyring), url: public_keys_path },
      { label: t("nav.server_groups"), url: server_groups_path },
      { label: t("nav.activity"), url: activities_path },
      { label: t("nav.tasks"), hint: hint.(:tasks), url: tasks_path },
      *Integration.sidebar_links.map { |link| { label: link[:label], hint: hint.(:extension), url: public_send(link[:path]) } }
    ]
    pages += [ { label: t("command_palette.import_servers"), hint: hint.(:import), url: new_server_import_path }, { label: t("command_palette.add_server"), url: new_server_path },
               { label: t("command_palette.add_key"), url: new_public_key_path } ] if can?(:operate)
    pages += [
      { label: t("nav.settings"), hint: hint.(:settings), url: settings_path },
      { label: t("command_palette.notifications"), hint: hint.(:settings_page), url: settings_notifications_path },
      { label: t("nav.automations"), hint: hint.(:automations), url: settings_automations_path },
      { label: t("command_palette.vulnerability_feeds"), hint: hint.(:vulnerability_feeds), url: settings_vulnerabilities_path },
      { label: t("nav.docker"), hint: hint.(:docker_settings), url: settings_docker_path },
      { label: t("command_palette.jobs"), hint: "Mission Control", url: "/jobs" }
    ] if can?(:administer)
    pages = pages.map { |page| page.merge(group: t("command_palette.pages")) }

    groups = ServerGroup.order(:name).map { |group| { group: t("command_palette.groups"), label: group.name, hint: hint.(:group), url: servers_path(group: group.id) } }
    dns_names = DnsRecord.attached.distinct.pluck(:server_id, :name).group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    servers = Server.order(:name).includes(:server_groups, :inventory_snapshots).map do |server|
      { group: t("command_palette.servers"), label: server.name, hint: [ "#{server.username}@#{server.host}", server.distinct_hostname, *server.server_groups.map(&:name) ].compact.join(" · "),
        url: server_path(server), keywords: ([ server.hostname ] + server.addresses + dns_names.fetch(server.id, [])).compact.uniq.join(" ").presence, server: true }.compact
    end
    public_keys = PublicKey.order(:name).map { |public_key| { group: t("command_palette.keyring"), label: public_key.name, hint: public_key.kind_label, url: public_key_path(public_key) } }
    pages + groups + servers + public_keys
  end

  # PublicKey name proposed for an authorized key: its comment without the host
  # part ("alice@laptop" → "alice"), or nothing for an unnamed key.
  def suggested_public_key_name(key)
    key.comment&.split("@")&.first.presence
  end
end
