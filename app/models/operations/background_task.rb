# A background task started by someone (or by an automation), followed on the
# "Tâches" page: an inventory, a keys scan, an automation run. One item per
# server, updated by the jobs; the task's status is derived from its items.
# The technical view of the queue itself is Mission Control (/jobs, admins).
class BackgroundTask < ApplicationRecord
  KINDS = %w[inventory keys_scan automation integration vulnerabilities].freeze
  STATUSES = %w[queued running succeeded partial failed].freeze
  FINISHED = %w[succeeded partial failed].freeze
  # Status filters of the page: "à venir", "en cours", "terminées", "en échec".
  FILTERS = { "queued" => %w[queued], "running" => %w[running], "succeeded" => %w[succeeded], "failed" => %w[partial failed] }.freeze
  RETENTION = 30.days

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
  scope :expired, -> { finished.where(created_at: ...RETENTION.ago) }

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
  def self.enqueue!(kind:, label:, servers:, user: Current.user, automation: nil)
    task = transaction do
      create!(kind: kind, label: label, user: user, automation: automation).tap { |created| created.add_items!(servers) }
    end
    task.items.each { |item| yield item } if block_given?
    task.refresh!
  end

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
  def refresh!(result: self.result)
    with_lock do
      statuses = items.pluck(:status)
      self.result = result
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
      update!(status: "failed", result: message, started_at: started_at || Time.current, finished_at: Time.current)
    end
  end

  def progress
    counts = items.unscope(:order).group(:status).count
    done = counts.slice(*FINISHED).values.sum
    { done: done, total: counts.values.sum, failed: counts.fetch("failed", 0) + counts.fetch("partial", 0) }
  end

  def duration = started_at && (finished_at || Time.current) - started_at

  private

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
