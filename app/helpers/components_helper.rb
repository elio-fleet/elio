# The page-level components of the design system (catalogue: /design). A view
# never writes its own header, tabs, filters, tiles or panels: it calls these,
# so every page looks and behaves the same. Rules in app/views/CLAUDE.md.
module ComponentsHelper
  TONE_TEXT = { good: "text-good-ink", warn: "text-warn-ink", crit: "text-crit-ink", off: "text-crit-ink" }.freeze
  COUNT_CLASSES = { crit: "bg-crit-soft text-crit-ink", warn: "bg-warn-soft text-warn-ink" }.freeze

  # Header of a page: optional breadcrumb, title, badges, subtitle; the block
  # holds the actions (one btn-primary at most, then actions_menu).
  #   page_header t(".title"), subtitle: t(".subtitle"), crumbs: [[t("nav.servers"), servers_path], server.name] do … end
  def page_header(title, subtitle: nil, crumbs: nil, badges: nil, mono: false, id: nil, &actions)
    actions_html = capture(&actions) if actions
    tag.header(class: "page-header mb-5", id: id) do
      safe_join([
        (breadcrumbs(crumbs) if crumbs.present?),
        tag.div(class: "flex flex-wrap items-start justify-between gap-x-4 gap-y-3") do
          safe_join([
            tag.div(class: "min-w-0 flex-1") do
              safe_join([
                tag.div(class: "flex flex-wrap items-center gap-2") do
                  safe_join([ tag.h1(title, class: "page-title text-xl font-semibold tracking-tight #{"font-mono" if mono}"), badges ].compact)
                end,
                (tag.div(subtitle, class: "page-subtitle mt-0.5 text-xs text-ink-3") if subtitle.present?)
              ].compact)
            end,
            (tag.div(actions_html, class: "page-actions flex flex-wrap items-center gap-2 sm:shrink-0") if actions_html.present?)
          ].compact)
        end
      ].compact)
    end
  end

  # Breadcrumb: items are [label, path] or a plain label (the current page).
  def breadcrumbs(items)
    tag.nav(class: "breadcrumbs mb-1 text-xs text-ink-3", aria: { label: t("ui.breadcrumb") }) do
      tag.ol(class: "flex flex-wrap items-center gap-1") do
        safe_join(items.each_with_index.map do |(label, path), index|
          tag.li(class: "flex items-center gap-1") do
            safe_join([
              (tag.span("/", class: "text-line", aria: { hidden: true }) if index.positive?),
              path ? link_to(label, path, class: "hover:text-ink") : tag.span(label, aria: { current: "page" })
            ].compact)
          end
        end)
      end
    end
  end

  # The "⋯" menu of a page or a row: secondary and dangerous actions.
  # Items: menu_item, menu_separator.
  def actions_menu(label: t("ui.more_actions"), id: nil, align: :right, &block)
    render "shared/actions_menu", label: label, id: id, align: align, items: capture(&block)
  end

  # An item of a menu: a link, or a button (method:) with an optional
  # confirmation. danger: in red, always after a menu_separator.
  def menu_item(label, path, icon: nil, method: nil, danger: false, confirm: nil, **options)
    classes = "dropdown-item flex w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-subtle focus:bg-subtle focus:outline-none #{danger ? "text-crit-ink" : "text-ink-2 hover:text-ink"}"
    content = safe_join([ (icon(icon, class: "h-4 w-4 shrink-0") if icon), tag.span(label) ].compact)
    data = options.delete(:data) || {}
    data = data.merge(turbo_confirm: confirm, confirm_variant: (danger ? "danger" : nil)).compact if confirm
    if method
      button_to path, method: method, class: classes, role: "menuitem", form: { class: "contents", data: data.slice(:turbo_confirm, :confirm_variant, :turbo_frame) },
                      data: data.except(:turbo_confirm, :confirm_variant), **options do
        content
      end
    else
      link_to path, class: classes, role: "menuitem", data: data, **options do
        content
      end
    end
  end

  def menu_separator = tag.div(class: "my-1 border-t border-line", role: "separator")

  # Row of stat tiles (4 at most). Each tile is a link that filters the list below.
  def stat_tiles(&block) = tag.div(class: "stat-tiles mb-5 grid grid-cols-2 gap-3 lg:grid-cols-4", &block)

  # One line of filters: search, selects, chips; the view toggle goes in filter_bar_end.
  def filter_bar(**options, &block)
    tag.div(class: "filter-bar mb-3 flex flex-wrap items-center gap-2 #{options.delete(:class)}", **options, &block)
  end

  def filter_bar_end(&block) = tag.div(class: "ml-auto flex flex-wrap items-center gap-2", &block)

  # A chip that filters a list (never a tab): active = dark, with a count and a coloured dot.
  def filter_chip(label, path, active: false, count: nil, dot: nil, **options)
    classes = "filter-chip inline-flex items-center gap-1.5 rounded-full border px-3 py-1 text-sm whitespace-nowrap #{active ? "border-ink bg-ink text-surface" : "border-line bg-surface text-ink-2 hover:border-ink-3 hover:text-ink"}"
    link_to path, class: classes, aria: { current: (active ? "true" : nil) }, **options do
      safe_join([
        (tag.span(class: "h-2 w-2 rounded-full #{dot}") if dot),
        tag.span(label),
        (tag.span(count, class: "text-xs tabular-nums #{active ? "opacity-70" : "text-ink-3"}") unless count.nil?)
      ].compact, " ")
    end
  end

  # Segmented list / grid switch: options [[key, label, icon, path], …].
  def view_toggle(options, current:, label: t("ui.view"))
    tag.div(class: "view-toggle inline-flex rounded-lg border border-line bg-surface p-0.5", role: "group", aria: { label: label }) do
      safe_join(options.map do |key, text, icon_name, path|
        active = key.to_s == current.to_s
        link_to path, class: "inline-flex items-center gap-1.5 rounded-md px-2.5 py-1 text-xs #{active ? "bg-subtle font-medium text-ink" : "text-ink-3 hover:text-ink"}",
                      aria: { pressed: active }, data: { view: key } do
          safe_join([ icon(icon_name, class: "h-3.5 w-3.5"), tag.span(text) ])
        end
      end)
    end
  end

  # The one style of tabs: items [{ key:, label:, path:, count:, tone: }]; those
  # that do not fit go into a "More" menu (overflow-tabs controller).
  def tabs(items, current:, label:, **options)
    render "shared/tabs", items: items, current: current.to_s, label: label, extra_class: options[:class]
  end

  def tab_count(count, tone = nil)
    tag.span(count, class: "tab-count rounded-full px-1.5 text-[11px] tabular-nums #{COUNT_CLASSES.fetch(tone&.to_sym, "bg-subtle text-ink-2")}", data: { tone: tone })
  end

  # A card with a header: title (and icon) on the left, meta or a link on the right.
  #   panel t(".health"), meta: relative_time_tag(at), link: [t(".history"), path] do … end
  def panel(title = nil, meta: nil, link: nil, icon: nil, id: nil, clip: true, header: nil, **options, &block)
    tag.section(class: "panel card #{"overflow-hidden" if clip} #{options.delete(:class)}", id: id, **options) do
      safe_join([
        (tag.div(class: "card-header") do
          safe_join([
            tag.h2(class: "flex min-w-0 items-center gap-2 text-sm font-semibold") { safe_join([ (icon(icon, class: "h-4 w-4 text-ink-3") if icon), title ].compact) },
            tag.div(class: "flex shrink-0 items-center gap-3 text-xs text-ink-3") do
              safe_join([ meta, header, (link_to(link[0], link[1], class: "text-accent hover:underline") if link) ].compact)
            end
          ])
        end if title),
        capture(&block)
      ].compact)
    end
  end

  # Compact label → value list (two columns); pairs [[label, value], …], nil values skipped.
  def fact_list(pairs, **options)
    tag.dl(class: "fact-list grid grid-cols-[auto_minmax(0,1fr)] text-sm #{options.delete(:class)}", **options) do
      safe_join(pairs.reject { |_, value| value.nil? }.each_with_index.flat_map do |(label, value), index|
        border = index.zero? ? "" : "border-t border-line"
        [ tag.dt(label, class: "#{border} px-4 py-1.5 text-xs leading-5 text-ink-3"),
          tag.dd(value, class: "#{border} min-w-0 px-4 py-1.5 text-right break-words") ]
      end)
    end
  end

  # A line of "To handle": gravity icon, text, servers as chips, a named action.
  def attention_item(tone, text, action: nil, servers: [], icon: nil, **options)
    tag.li(class: "attention-item grid grid-cols-[1rem_minmax(0,1fr)_auto] items-center gap-3 border-t border-line px-4 py-2 first:border-t-0", data: { tone: tone }, **options) do
      safe_join([
        icon(icon || UiHelper::TONES.fetch(tone)[:icon] || :information_circle, class: "h-4 w-4 #{TONE_TEXT.fetch(tone, "text-ink-3")}"),
        tag.div(class: "min-w-0") do
          safe_join([ tag.span(text), *Array(servers).map { |name, path| server_chip(name, path) } ], " ")
        end,
        (link_to(safe_join([ action[0], " →" ]), action[1], class: "attention-action text-sm whitespace-nowrap text-accent hover:underline", data: action[2]) if action)
      ].compact)
    end
  end

  def attention_list(**options, &block) = tag.ul(class: "attention-list #{options.delete(:class)}", **options, &block)

  # A server's name as a small monospace chip (optionally a link).
  def server_chip(name, path = nil)
    classes = "server-chip rounded-md bg-subtle px-1.5 font-mono text-xs whitespace-nowrap text-ink-2"
    path ? link_to(name, path, class: "#{classes} hover:text-ink") : tag.span(name, class: classes)
  end

  # States on one line: items [{ label:, tone:, text:, title: }], extra content in the block.
  def status_line(items, **options, &block)
    tag.div(class: "status-line card flex flex-wrap items-center gap-x-5 gap-y-2 px-4 py-2 text-sm #{options.delete(:class)}", **options) do
      safe_join([
        *items.map do |item|
          tag.span(class: "flex items-center gap-2", data: { status: item[:key] }, title: item[:title]) do
            safe_join([ tag.span(item[:label], class: "text-[11px] font-semibold tracking-wider text-ink-3 uppercase"), status_badge(item[:tone], item[:text]) ])
          end
        end,
        (tag.span(class: "ml-auto flex items-center gap-2 text-xs text-ink-3", &block) if block)
      ].compact)
    end
  end

  # An empty list that says why and what to do (the block holds the action).
  def empty_state(title, text = nil, icon: :information_circle, **options, &action)
    tag.div(class: "empty-state flex flex-col items-center gap-1.5 px-4 py-8 text-center text-sm #{options.delete(:class)}", **options) do
      safe_join([
        tag.span(icon(icon, class: "h-5 w-5"), class: "mb-1 grid h-9 w-9 place-items-center rounded-lg bg-subtle text-ink-3"),
        tag.p(title, class: "font-medium text-ink"),
        (tag.p(text, class: "max-w-md text-ink-3") if text),
        (tag.div(class: "mt-2", &action) if action)
      ].compact)
    end
  end

  # An entry of a journal (event or note): round icon or initials, title, meta, optional note body.
  def timeline_item(title, meta:, icon: nil, tone: nil, initials: nil, note: nil, **options)
    circle = { crit: "bg-crit-soft text-crit-ink", warn: "bg-warn-soft text-warn-ink", good: "bg-good-soft text-good-ink", note: "bg-accent-soft text-accent" }.fetch(tone&.to_sym, "bg-subtle text-ink-2")
    tag.li(class: "timeline-item grid grid-cols-[1.75rem_minmax(0,1fr)] gap-3 border-t border-line px-4 py-2.5 first:border-t-0", **options) do
      safe_join([
        tag.span(class: "grid h-7 w-7 place-items-center rounded-full text-[11px] font-semibold #{circle}") { initials || icon(icon || :information_circle, class: "h-3.5 w-3.5") },
        tag.div(class: "min-w-0") do
          safe_join([
            tag.div(title, class: "text-sm"),
            (tag.div(note, class: "prose-note mt-1 rounded-lg border border-line bg-subtle/60 px-3 py-2 text-sm") if note),
            tag.div(meta, class: "mt-0.5 text-xs text-ink-3")
          ].compact)
        end
      ])
    end
  end

  def timeline(**options, &block) = tag.ol(class: "timeline #{options.delete(:class)}", **options, &block)

  # A day separator inside a timeline or a list.
  def list_divider(label) = tag.li(label, class: "list-divider border-t border-line bg-subtle/60 px-4 py-1.5 text-[11px] font-semibold tracking-wider text-ink-3 uppercase first:border-t-0")

  # A server group: neutral label with its colour dot (never a coloured badge).
  def group_tag(group, path: nil)
    content = safe_join([ tag.span(class: "h-2 w-2 shrink-0 rounded-full #{group.dot_classes}"), tag.span(group.name) ])
    classes = "group-tag inline-flex items-center gap-1.5 text-xs whitespace-nowrap text-ink-2"
    path ? link_to(content, path, class: "#{classes} hover:text-ink") : tag.span(content, class: classes)
  end

  # Where a piece of data comes from (Uptime Kuma, Gandi…): a neutral small pill.
  def source_tag(label) = tag.span(label, class: "source-tag inline-flex rounded-full bg-subtle px-2 text-[11px] whitespace-nowrap text-ink-2")

  # A titled block of a form: title and help on the left, fields on the right.
  def form_section(title, help = nil, **options, &block)
    tag.section(class: "form-section grid gap-x-8 gap-y-3 border-t border-line py-5 first-of-type:border-t-0 first-of-type:pt-0 md:grid-cols-[14rem_minmax(0,1fr)] #{options.delete(:class)}", **options) do
      safe_join([
        tag.div { safe_join([ tag.h2(title, class: "text-sm font-semibold"), (tag.p(help, class: "mt-1 text-xs text-ink-3") if help) ].compact) },
        tag.div(class: "min-w-0 space-y-4", &block)
      ])
    end
  end

  # The one Save of a page: hidden until a field changes (dirty-form controller on the form).
  def save_bar(form, label: t("ui.save"))
    render "shared/save_bar", form: form, label: label
  end
end
