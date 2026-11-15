# Display of the background tasks (see BackgroundTask).
module TasksHelper
  # Tone and icon of each status (labels: tasks_helper.statuses.*).
  TASK_STATUSES = {
    "queued" => [ :neutral, :clock ], "running" => [ :accent, :arrow_path ], "succeeded" => [ :good, :check ],
    "partial" => [ :warn, :exclamation_triangle ], "failed" => [ :crit, :x_mark ]
  }.freeze

  def task_status_badge(status, **options)
    tone, icon = TASK_STATUSES.fetch(status.to_s)
    status_badge(tone, t("tasks_helper.statuses.#{status}"), icon: icon, data: { status: status }, **options)
  end

  # 72 s → "1 min 12 s", 4 s → "4 s".
  def task_duration(seconds)
    return "—" unless seconds

    seconds = seconds.round
    seconds < 60 ? "#{seconds} s" : "#{seconds / 60} min #{format("%02d", seconds % 60)} s"
  end

  # 1234 ms → "1.2 s" (with the separator of the language), 72 000 ms → "1 min 12 s".
  def short_duration(milliseconds)
    return "—" unless milliseconds

    milliseconds < 10_000 ? "#{number_with_precision(milliseconds / 1000.0, precision: 1)} s" : task_duration(milliseconds / 1000.0)
  end

  def task_filter_count(filter)
    BackgroundTask::FILTERS.fetch(filter).sum { |status| @counts.fetch(status, 0) }
  end
end
