# Building blocks of the interface (direction A, see docs/design/), drawn
# with the design tokens of app/assets/tailwind/application.css. A state
# colour is never shown alone: badges always carry an icon and a label.
module UiHelper
  TONES = {
    good: { badge: "bg-good-soft text-good-ink", icon: :check },
    warn: { badge: "bg-warn-soft text-warn-ink", icon: :exclamation_triangle },
    crit: { badge: "bg-crit-soft text-crit-ink", icon: :x_mark },
    off: { badge: "bg-crit-soft text-crit-ink", icon: :signal_slash },
    neutral: { badge: "bg-subtle text-ink-2", icon: nil },
    accent: { badge: "bg-accent-soft text-accent", icon: nil }
  }.freeze

  # Pill with an icon and a label, e.g. status_badge(:crit, "Critique").
  def status_badge(tone, label, icon: TONES.fetch(tone)[:icon], **options)
    classes = [ "badge", TONES.fetch(tone)[:badge], options.delete(:class) ].compact.join(" ")
    tag.span(class: classes, **options) do
      safe_join([ (icon(icon, class: "h-3.5 w-3.5") if icon), label ].compact)
    end
  end

  # Horizontal gauge of a percentage: neutral fill, warning colour from `warn`,
  # critical colour from `crit`. Shows the value next to it unless `value: false`.
  def meter(percent, warn: 80, crit: 90, width: "w-16", value: true, label: nil)
    return tag.span("—", class: "text-ink-3") if percent.nil?

    percent = percent.to_f.clamp(0, 100)
    tone = percent >= crit ? :crit : percent >= warn ? :warn : :neutral
    fill = { crit: "bg-crit", warn: "bg-warn", neutral: "bg-ink-2" }.fetch(tone)

    tag.div(class: "meter flex items-center gap-2", data: { tone: tone }) do
      safe_join([
        (tag.span(label, class: "w-12 text-xs text-ink-3") if label),
        tag.div(class: "h-1.5 #{width} overflow-hidden rounded-full bg-track", role: "meter",
                aria: { valuenow: percent.round, valuemin: 0, valuemax: 100, label: label }) do
          tag.div(class: "h-full rounded-full #{fill}", style: "width: #{percent.round(1)}%")
        end,
        (tag.span(number_to_percentage(percent, precision: 0), class: "w-10 text-right text-xs tabular-nums #{tone == :crit ? "font-semibold text-crit-ink" : "text-ink-2"}") if value)
      ].compact)
    end
  end

  # Small trend line (2 px), values between 0 and `max`; the last point is marked.
  def sparkline(values, width: 72, height: 20, max: nil, color: "var(--color-spark)", title: nil)
    values = Array(values).compact.map(&:to_f)
    return tag.span("—", class: "text-ink-3") if values.size < 2

    max = [ max || values.max, 1e-9 ].max
    step = (width - 4).fdiv(values.size - 1)
    points = values.each_with_index.map { |v, i| [ 2 + i * step, height - 2 - (v.clamp(0, max) / max) * (height - 4) ] }
    path = points.each_with_index.map { |(x, y), i| "#{i.zero? ? "M" : "L"}#{x.round(1)},#{y.round(1)}" }.join(" ")
    last_x, last_y = points.last

    tag.svg(width: width, height: height, viewBox: "0 0 #{width} #{height}", class: "sparkline overflow-visible",
            role: "img", aria: { label: title || t("ui.trend") }) do
      safe_join([
        (tag.title(title) if title),
        tag.path(d: path, fill: "none", stroke: color, "stroke-width" => 2, "stroke-linecap" => "round", "stroke-linejoin" => "round"),
        tag.circle(cx: last_x.round(1), cy: last_y.round(1), r: 2.5, fill: color)
      ].compact)
    end
  end

  # Instant search: the filter form (outside the frame) reloads only this
  # frame, so the search field keeps its focus, its caret and what was typed
  # while the request ran. Links inside the frame still navigate the page;
  # the address follows the results (auto_submit_controller.js).
  def search_results_frame(id = "search-results", &block)
    turbo_frame_tag id, target: "_top", class: "block", &block
  end

  def search_form_data(frame = "search-results")
    { controller: "auto-submit", turbo_frame: frame }
  end

  # Headline figure with a label and a caption, optionally toned.
  def stat_tile(label, value, caption = nil, tone: nil, icon: nil, id: nil)
    value_class = { good: "text-good-ink", warn: "text-warn-ink", crit: "text-crit-ink", off: "text-crit-ink" }.fetch(tone, "text-ink")
    tag.div(class: "stat-tile card px-4 py-3", id: id) do
      safe_join([
        tag.p(class: "flex items-center gap-1.5 text-xs text-ink-3") { safe_join([ (icon(icon, class: "h-3.5 w-3.5") if icon), label ].compact) },
        tag.p(value, class: "stat-value mt-1 text-2xl font-semibold tabular-nums #{value_class}"),
        (tag.p(caption, class: "text-xs text-ink-3") if caption)
      ].compact)
    end
  end

  # Link of the sidebar navigation, highlighted (and aria-current) when active.
  def sidebar_link(label, path, icon:, active:, count: nil, **options)
    classes = "flex items-center gap-2.5 rounded-lg px-2.5 py-1.5 text-sm #{active ? "bg-accent-soft font-medium text-accent" : "text-ink-2 hover:bg-subtle hover:text-ink"}"
    link_to path, class: classes, aria: { current: (active ? "page" : nil) }, **options do
      safe_join([ icon(icon, class: "h-4 w-4"), tag.span(label), (tag.span(count, class: "ml-auto text-xs text-ink-3") if count) ].compact)
    end
  end

  # Server groups listed in the sidebar, with their number of servers.
  def sidebar_server_groups
    ServerGroup.left_joins(:memberships).group(:id).order(:name)
               .select("server_groups.*, COUNT(server_group_memberships.id) AS servers_count")
  end

  # Line chart of a percentage over time (24 h by default), stretched to the
  # width of its container: grid at 0/50/100 %, optional dashed threshold, and
  # one hover zone per point with its time and value (native tooltip). Labels
  # are HTML around the drawing so they keep their size.
  def history_chart(points, label:, threshold: nil, color: "var(--color-accent)", from: 24.hours.ago, to: Time.current, height: 96)
    points = points.select { |time, value| value && time >= from }
    span = (to - from).to_f
    x = ->(time) { ((time - from) / span * 100).clamp(0, 100).round(2) }
    y = ->(value) { (100 - value.to_f.clamp(0, 100)).round(2) }
    line = points.map.with_index { |(time, value), i| "#{i.zero? ? "M" : "L"}#{x.(time)},#{y.(value)}" }.join(" ")
    zones = points.each_cons(2).map { |(a, _), (b, _)| (x.(b) - x.(a)) / 2 }
    zones = [ 0, *zones, 0 ]

    svg = tag.svg(viewBox: "0 0 100 100", preserveAspectRatio: "none", class: "block w-full overflow-visible", style: "height: #{height}px",
                  role: "img", aria: { label: t("ui.over_24_hours", label: label) }) do
      safe_join([
        *[ 0, 50, 100 ].map { |v| tag.line(x1: 0, x2: 100, y1: y.(v), y2: y.(v), stroke: "var(--color-line)", "vector-effect" => "non-scaling-stroke") },
        (tag.line(x1: 0, x2: 100, y1: y.(threshold), y2: y.(threshold), stroke: "var(--color-warn)", "stroke-dasharray" => "4 3",
                  "vector-effect" => "non-scaling-stroke", class: "chart-threshold") if threshold),
        (tag.path(d: line, fill: "none", stroke: color, "stroke-width" => 2, "stroke-linejoin" => "round", "vector-effect" => "non-scaling-stroke") if points.size > 1),
        *points.each_with_index.map do |(time, value), i|
          left = x.(time) - zones[i]
          tag.rect(x: left, y: 0, width: [ zones[i] + zones[i + 1], 0.5 ].max, height: 100, fill: "transparent", class: "chart-point") do
            tag.title("#{l(time, format: "%H:%M")} — #{number_to_percentage(value, precision: 0)}")
          end
        end
      ].compact)
    end

    tag.figure(class: "history-chart") do
      safe_join([
        tag.figcaption(class: "flex items-baseline justify-between text-xs") do
          safe_join([ tag.span(label, class: "font-medium text-ink-2"),
                      tag.span(points.any? ? t("ui.now", value: number_to_percentage(points.last.last, precision: 0)) : t("ui.no_measure"), class: "text-ink-3") ])
        end,
        tag.div(class: "relative mt-1.5 pl-7") do
          safe_join([
            tag.div(class: "absolute inset-y-0 left-0 flex flex-col justify-between text-[10px] text-ink-3") { safe_join([ tag.span("100"), tag.span("50"), tag.span("0") ]) },
            svg
          ])
        end,
        tag.div(class: "mt-1 flex justify-between pl-7 text-[10px] text-ink-3") { safe_join([ tag.span(t("ui.hours_ago_24")), tag.span(t("ui.hours_12")), tag.span(t("ui.now_axis")) ]) }
      ])
    end
  end
end
