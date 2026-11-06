# A recurring task configured from the settings (one row per kind, created on
# first access). RunDueAutomationsJob runs every minute (config/recurring.yml)
# and starts the enabled automations whose interval has elapsed. Each one runs
# on the whole fleet or on some server groups (server_group_ids).
class Automation < ApplicationRecord
  # `categories`: inventory categories collected (Inventory::Collection) by the
  # inventory kinds. `default_enabled`: state of a new installation. `quiet`:
  # frequent tasks whose runs are not logged (what they find still is).
  # `integration`: synchronization of an extension (Integration), only
  # available while the extension is enabled.
  # Labels and descriptions: automation.kinds.<key>.label|description.
  Definition = Data.define(:key, :default_interval, :categories, :default_enabled, :quiet, :integration) do
    def initialize(key:, default_interval:, categories: nil, default_enabled: false, quiet: false, integration: nil) = super
    def label = I18n.t("automation.kinds.#{key}.label")
    def description = I18n.t("automation.kinds.#{key}.description")
    def inventory? = categories.present?
    def available? = integration.nil? || Integration.enabled?(integration)
  end

  KINDS = [
    Definition.new(key: :health_check, default_interval: 15, categories: %w[health], default_enabled: true, quiet: true),
    Definition.new(key: :servers_ping, default_interval: 15, quiet: true),
    Definition.new(key: :inventory_os, default_interval: 1440, categories: %w[os network]),
    Definition.new(key: :inventory_packages, default_interval: 360, categories: %w[packages]),
    Definition.new(key: :inventory_services, default_interval: 60, categories: %w[services scheduled_tasks docker]),
    Definition.new(key: :inventory_ports, default_interval: 60, categories: %w[ports]),
    Definition.new(key: :vulnerabilities_update, default_interval: 1440, default_enabled: true),
    Definition.new(key: :cve_scores_update, default_interval: 360, default_enabled: true),
    Definition.new(key: :docker_image_updates, default_interval: 360, default_enabled: true),
    Definition.new(key: :keys_scan, default_interval: 360),
    Definition.new(key: :uptime_kuma_sync, default_interval: 15, default_enabled: true, quiet: true, integration: "uptime_kuma"),
    Definition.new(key: :ovh_sync, default_interval: 360, default_enabled: true, integration: "ovh"),
    Definition.new(key: :technitium_sync, default_interval: 60, default_enabled: true, quiet: true, integration: "technitium")
  ].index_by(&:key).freeze

  INTERVALS = [ 5, 15, 60, 360, 1440 ].freeze

  def self.interval_label(minutes) = I18n.t("automation.intervals.i#{minutes}")

  def self.interval_options = INTERVALS.map { |minutes| [ interval_label(minutes), minutes ] }

  # The label of a kind, also for a kind no longer defined (old activities).
  def self.label_for(kind) = KINDS.key?(kind.to_sym) ? KINDS.fetch(kind.to_sym).label : kind.to_s.humanize

  normalizes :server_group_ids, with: ->(ids) { Array(ids).compact_blank.map(&:to_i).uniq.sort }

  validates :kind, inclusion: { in: KINDS.keys.map(&:to_s) }, uniqueness: true
  validates :interval_minutes, inclusion: { in: INTERVALS }

  # Every automation, in KINDS order, created with its default interval and state.
  # Automations offered in the interface (those of a disabled extension aside).
  def self.available = all_kinds.select(&:available?)

  def self.all_kinds
    KINDS.values.map do |definition|
      find_or_create_by!(kind: definition.key.to_s) do |automation|
        automation.interval_minutes = definition.default_interval
        automation.enabled = definition.default_enabled
      end
    end
  end

  # Returned by run! when the same automation runs elsewhere.
  def self.already_running = I18n.t("automation.already_running")

  def definition = KINDS.fetch(kind.to_sym)

  # Runs an automation now because something needs it (a release new to the
  # fleet needs the vulnerability feeds, new CVEs need their scores), unless
  # it is disabled — a closed network turns it off — or already waiting or
  # running. Returns the task, or nil.
  def self.trigger(kind)
    automation = all_kinds.find { |candidate| candidate.kind == kind.to_s }
    start = automation.with_lock do
      automation.enabled? && automation.available? && !BackgroundTask.unfinished.exists?(automation: automation)
    end
    automation.enqueue!(tracked: true) if start
  end

  delegate :label, :description, :inventory?, :available?, to: :definition

  def server_groups = ServerGroup.where(id: server_group_ids).order(:name)

  # Servers the automation runs on: its groups, or the whole fleet.
  def servers
    scope = server_group_ids.any? ? Server.where(id: ServerGroupMembership.where(server_group_id: server_group_ids).select(:server_id)) : Server.all
    scope.order(:name)
  end

  def scope_label = server_group_ids.any? ? server_groups.map(&:name).join(", ") : I18n.t("automation.whole_fleet")

  def interval = interval_minutes.minutes

  def next_run_at = enabled? ? (last_run_at ? last_run_at + interval : Time.current) : nil

  def due?(now = Time.current) = enabled? && available? && (last_run_at.nil? || last_run_at + interval <= now)

  # Runs the task now, remembers its result and logs an automation_run
  # activity (except for the quiet ones).
  # Enqueues a run, followed on the "Tâches" page except for the quiet
  # automations started on schedule. Returns the task (or nil).
  def enqueue!(user: nil, tracked: !definition.quiet)
    task = BackgroundTask.enqueue!(kind: "automation", label: label, servers: [], user: user, automation: self) if tracked
    RunAutomationJob.perform_later(self, task)
    task
  end

  # "Lancer maintenant": the task already waiting or running if there is one
  # (a second run would only wait for the first), else a new one.
  # Returns [task, started].
  def start_now!(user:)
    running = BackgroundTask.unfinished.where(automation: self).order(:id).last
    running ? [ running, false ] : [ enqueue!(user: user, tracked: true), true ]
  end

  # With a BackgroundTask (see RunAutomationJob), one item per server is followed.
  # Never twice at the same time (two workers, a run started by hand while the
  # scheduled one runs): the second run is skipped and says so.
  def run!(task: nil)
    @task = task
    result = AdvisoryLock.try("automation:#{kind}") do
      if inventory? then run_inventory
      elsif definition.integration then run_integration_sync
      else send("run_#{kind}")
      end
    end
    return self.class.already_running if result.equal?(AdvisoryLock::HELD)

    update!(last_run_at: Time.current, last_result: result)
    Activity.record!(:automation_run, user: nil, automation: kind, automation_label: label, result: result) unless definition.quiet
    result
  end

  private

  # Collects the automation's categories on its servers, a few at a time.
  def run_inventory
    servers = self.servers.to_a
    collected = each_tracked(servers) do |server, item|
      outcomes = Inventory::Collection.call(server, categories: definition.categories)
      item&.finish_inventory!(outcomes)
      outcomes.values.none? { |outcome| outcome.status == "error" }
    end
    I18n.t("automation.results.inventoried", done: collected.count(true), count: servers.size)
  end

  def run_keys_scan
    servers = self.servers.to_a
    detected_before = Activity.of_kind(:unknown_key_detected).count
    scanned = each_tracked(servers) do |server, item|
      scan = Keys::ServerScan.call(server)
      item&.finish!(scan.success? ? :succeeded : :failed, scan.error_title)
      scan.success?
    end.count(true)
    detected = Activity.of_kind(:unknown_key_detected).count - detected_before

    I18n.t("automation.results.scanned", done: scanned, count: servers.size, keys: I18n.t("automation.results.new_unknown_keys", count: detected))
  end

  # Runs the block on each server, a few at a time, with its task item (if any).
  def each_tracked(servers)
    @task&.add_items!(servers)
    items = @task ? @task.items.index_by(&:server_id) : {}
    BoundedParallel.map(servers) do |server|
      item = items[server.id]
      item&.update!(status: "running", started_at: Time.current)
      yield server, item
    end
  end

  # Synchronization of an extension (does nothing once it is disabled).
  def run_integration_sync
    integration = Integration.find_enabled(definition.integration)
    return I18n.t("automation.extension_off") unless integration

    integration.sync!
  rescue Integrations::Error => e
    I18n.t("automation.failed", message: e.message)
  end

  # Downloads the feeds of the releases used on the fleet. A failure is
  # logged once (vulnerability_feed_failed), until a download works again.
  def run_vulnerabilities_update
    Vulnerability::SOURCES.keys.map do |source|
      feed = VulnerabilityFeed.for(source)
      failing = feed.failed?
      Vulnerabilities::Update.call(source)
    rescue Vulnerabilities::Error => e
      Activity.record!(:vulnerability_feed_failed, user: nil, feed: feed.label, error: e.message) unless failing
      I18n.t("automation.feed_failed", label: feed.label, message: e.message)
    end.join(" · ").tap do
      # CVEs never asked to the score providers (the first download, a new
      # release): their scores now, not at the next run in a few hours.
      Automation.trigger(:cve_scores_update) if ServerVulnerability.where.not(cve: CveScore.select(:cve)).exists?
    end
  end

  def run_docker_image_updates = ImageRegistry::UpdateCheck.call

  def run_cve_scores_update = Vulnerabilities::Scores.update_all

  def run_servers_ping
    results = Servers::Ping.check_all!(servers)
    I18n.t("automation.results.reachable", done: results.values.count(true), count: results.size)
  end
end
