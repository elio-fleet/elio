# A background task started by someone (or by an automation), followed on the
# "Tâches" page: an inventory, a keys scan, an automation run. One item per
# server, updated by the jobs; the task's status is derived from its items.
# The technical view of the queue itself is Mission Control (/jobs, admins).
class BackgroundTask < ApplicationRecord
  KINDS = %w[inventory keys_scan key_rotation_check automation integration vulnerabilities].freeze
  STATUSES = %w[queued running succeeded partial failed].freeze
  FINISHED = %w[succeeded partial failed].freeze
  # Status filters of the page: "à venir", "en cours", "terminées", "en échec".
  FILTERS = { "queued" => %w[queued], "running" => %w[running], "succeeded" => %w[succeeded], "failed" => %w[partial failed] }.freeze
  RETENTION = 30.days
  # Runs that can be started again on their servers (all, or only the failed
  # ones), with the job of each server; a key rotation check is for admins.
  SERVER_JOBS = { "inventory" => "Inventory::CollectJob", "keys_scan" => "ScanServerJob", "key_rotation_check" => "CheckKeyRotationJob" }.freeze
  ADMIN_RERUNS = %w[key_rotation_check automation].freeze
  RERUN_KEYS = %w[background_task.rerun_label background_task.rerun_failed_label].freeze
  # A server is "slow" in a run from this duration (and twice the median).
  SLOW_MIN = 10.seconds

  belongs_to :user, optional: true
  belongs_to :automation, optional: true
  has_many :items, -> { order(:server_name, :id) }, class_name: "BackgroundTaskItem", inverse_of: :task, dependent: :delete_all

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :label, presence: true

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :unfinished, -> { where(status: %w[queued running]) }
  scope :finished, -> { where(status: FINISHED) }
  scope :filtered, ->(filter) { FILTERS.key?(filter.to_s) ? where(status: FILTERS[filter.to_s]) : all }
  scope :of_kind, ->(kind) { KINDS.include?(kind.to_s) ? where(kind: kind.to_s) : all }
  # Failed or partly failed, finished since `time` (the overview links to them).
  scope :failed_since, ->(time) { where(status: FILTERS["failed"], finished_at: time..) }
  scope :expired, -> { finished.where(created_at: ...RETENTION.ago) }
  # Keys scans, started by hand or by the planned "keys_scan" automation (the Keys page sums up the last one).
  scope :keys_scans, -> { where(kind: "keys_scan").or(where(kind: "automation", automation_id: Automation.where(kind: "keys_scan").select(:id))) }

  # Text search: the task's label and result, who started it, and the
  # servers and messages of its items ("Inventaire", "web-1", "timeout").
  def self.search(text)
    like = JournalSearch.like(text)
    items = BackgroundTaskItem.where("background_task_items.background_task_id = background_tasks.id")
                              .where("background_task_items.server_name ILIKE :q OR background_task_items.message ILIKE :q", q: like)
    left_joins(:user).where("background_tasks.label ILIKE :q OR background_tasks.result ILIKE :q OR users.email ILIKE :q", q: like).or(left_joins(:user).where(items.arel.exists))
  end

  # Creates the task and one queued item per server, then yields each item so
  # the caller enqueues its job: BackgroundTask.enqueue!(…) { |item| Job.perform_later(item.server, task_item: item) }.
  # `label`: a text, or a LocalizedText.part written in each reader's language
  # (the plain label, in the current language, stays for the text search).
  def self.enqueue!(kind:, label:, servers:, user: Current.user, automation: nil)
    localized = label.to_json if label.is_a?(Hash)
    task = transaction do
      create!(kind: kind, label: localized ? LocalizedText.render(localized) : label, localized_label: localized, user: user, automation: automation).tap { |created| created.add_items!(servers) }
    end
    task.items.each { |item| yield item } if block_given?
    task.refresh!
  end

  # The label in the reader's language when it was given as a LocalizedText.
  def label = localized_label ? LocalizedText.render(localized_label) : super

  # The result in the reader's language when it was given as a LocalizedText.
  def result = localized_result ? LocalizedText.render(localized_result) : super

  def add_items!(servers)
    now = Time.current
    rows = servers.map { |server| { background_task_id: id, server_id: server.id, server_name: server.name, created_at: now, updated_at: now } }
    BackgroundTaskItem.insert_all!(rows) if rows.any?
    items.reset
  end

  def kind_label = I18n.t("background_task.kinds.#{kind}")
  def author_name = user&.email || I18n.t("background_task.system")
  def finished? = FINISHED.include?(status)
  def unfinished? = !finished?

  def start!
    update!(status: "running", started_at: started_at || Time.current)
  end

  # Recomputes the status from the items (under a lock: several jobs finish
  # their item at the same time). A task without items is done once started.
  # `result`: a text or a LocalizedText (dump); left as it is when not given.
  def refresh!(result: nil)
    with_lock do
      statuses = items.pluck(:status)
      assign_result(result) unless result.nil?
      self.status = derived_status(statuses)
      self.started_at ||= items.minimum(:started_at) if status != "queued"
      self.finished_at = finished? ? (finished_at || Time.current) : nil
      save!
    end
    self
  end

  # A crash of the job itself (not of one server).
  def fail!(message)
    with_lock do
      items.where(status: %w[queued running]).update_all(status: "failed", message: I18n.t("background_task.interrupted"), finished_at: Time.current, updated_at: Time.current)
      update!(status: "failed", result: message, localized_result: nil, started_at: started_at || Time.current, finished_at: Time.current)
    end
  end

  def progress
    counts = items.unscope(:order).group(:status).count
    done = counts.slice(*FINISHED).values.sum
    { done: done, total: counts.values.sum, failed: counts.fetch("failed", 0) + counts.fetch("partial", 0) }
  end

  def duration = started_at && (finished_at || Time.current) - started_at

  # The items noticeably slower than the others of the run: more than twice
  # the median duration and at least SLOW_MIN, among at least 3 finished
  # servers (a run of 2 has no "usual" duration).
  def slow_item_ids(list = items)
    durations = list.filter_map { |item| [ item.id, item.duration ] if item.duration }
    return [] if durations.size < 3

    sorted = durations.map(&:last).sort
    median = (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
    durations.select { |_, duration| duration >= SLOW_MIN && duration > median * 2 }.map(&:first)
  end

  def rerun_permission = ADMIN_RERUNS.include?(kind) ? :administer : :operate

  # Whether the run can be started again: finished, on servers still there
  # (or an automation still offered).
  def rerunnable?
    return false if unfinished?
    return automation&.available? || false if kind == "automation"

    SERVER_JOBS.key?(kind) && items.any?(&:server_id)
  end

  # Whether only the servers that failed can be started again: a run on
  # servers (or an automation that collects or scans them) with failures.
  def failures_rerunnable?
    rerunnable? && rerun_server_job.present? && rerun_items(only_failed: true).any?
  end

  # Starts the run again, as a new task: on every server of the run, or
  # only those that failed. The servers that already wait or run for the
  # same kind of run are left out (they would be collected twice at the
  # same time). An automation started again in full goes through
  # start_now! (it waits for a run already there). Returns the new task, or
  # nil when every server is already busy.
  def rerun!(user:, only_failed: false)
    return automation.start_now!(user: user).first if kind == "automation" && !only_failed

    new_kind, job = rerun_server_job
    return unless job

    busy = BackgroundTaskItem.unfinished.joins(:task).where(background_tasks: { kind: new_kind }).select(:server_id)
    servers = Server.where(id: rerun_items(only_failed: only_failed).map(&:server_id)).where.not(id: busy).order(:name).to_a
    return if servers.empty?

    BackgroundTask.enqueue!(kind: new_kind, label: rerun_label(only_failed, servers.size), servers: servers, user: user) { |item| job.call(item) }
  end

  private

  def assign_result(value)
    localized = value.is_a?(String) && value.start_with?(LocalizedText::PREFIX)
    self.localized_result = localized ? value : nil
    self[:result] = localized ? LocalizedText.render(value) : value
  end

  def rerun_items(only_failed:)
    items.select { |item| item.server_id && (!only_failed || %w[failed partial].include?(item.status)) }
  end

  # [kind of the new task, ->(item) { enqueues its job }]; an automation
  # that collects or scans servers is started again as an inventory (of its
  # categories) or a keys scan of those servers.
  def rerun_server_job
    if SERVER_JOBS.key?(kind)
      job = SERVER_JOBS.fetch(kind).constantize
      [ kind, ->(item) { job.perform_later(item.server, task_item: item) } ]
    elsif automation&.inventory?
      categories = automation.definition.categories
      [ "inventory", ->(item) { Inventory::CollectJob.perform_later(item.server, categories, task_item: item) } ]
    elsif automation&.kind == "keys_scan"
      [ "keys_scan", ->(item) { ScanServerJob.perform_later(item.server, task_item: item) } ]
    end
  end

  # "Inventaire du parc (relance)", in each reader's language; a run
  # started again keeps the label of the first one.
  def rerun_label(only_failed, count)
    original = localized_label ? JSON.parse(localized_label) : self[:label]
    original = original.dig("params", "label") if original.is_a?(Hash) && RERUN_KEYS.include?(original["key"])
    if only_failed
      LocalizedText.part("background_task.rerun_failed_label", label: original, servers: LocalizedText.part("count.servers", count: count))
    else
      LocalizedText.part("background_task.rerun_label", label: original)
    end
  end

  def derived_status(statuses)
    if statuses.empty?
      started_at ? "succeeded" : "queued"
    elsif statuses.all?("queued")
      started_at ? "running" : "queued"
    elsif statuses.any? { |value| %w[queued running].include?(value) }
      "running"
    elsif statuses.all?("succeeded")
      "succeeded"
    elsif statuses.all?("failed")
      "failed"
    else
      "partial"
    end
  end
end
