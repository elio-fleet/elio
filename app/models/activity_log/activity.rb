# Log of what happened (keys added / removed / detected, servers, settings…).
# Each kind is declared in KINDS with a label, a category and a severity, so a
# future notification system can let users pick which kinds notify them.
# Names are copied into `data` so entries stay readable after a deletion.
class Activity < ApplicationRecord
  # Labels and descriptions: activity.kinds.<key>.label|description.
  Kind = Data.define(:key, :category, :severity) do
    def label = I18n.t("activity.kinds.#{key}.label")
    def description = I18n.t("activity.kinds.#{key}.description")
  end

  CATEGORIES = %i[keys servers security configuration].freeze
  SEVERITIES = %i[info warning critical].freeze

  KINDS = [
    Kind.new(:key_added, :keys, :info),
    Kind.new(:key_removed, :keys, :info),
    Kind.new(:key_expired, :keys, :info),
    Kind.new(:unknown_key_detected, :security, :warning),
    Kind.new(:key_disappeared, :security, :warning),
    Kind.new(:ssh_access_lost, :security, :critical),
    Kind.new(:host_key_changed, :security, :critical),
    Kind.new(:server_unreachable, :servers, :warning),
    Kind.new(:server_back_online, :servers, :info),
    Kind.new(:os_upgraded, :servers, :info),
    Kind.new(:server_rebooted, :servers, :info),
    Kind.new(:health_warning, :servers, :warning),
    Kind.new(:health_critical, :servers, :critical),
    Kind.new(:health_recovered, :servers, :info),
    Kind.new(:docker_warning, :servers, :warning),
    Kind.new(:docker_critical, :servers, :critical),
    Kind.new(:docker_recovered, :servers, :info),
    Kind.new(:packages_changed, :servers, :info),
    Kind.new(:service_failed, :servers, :warning),
    Kind.new(:service_recovered, :servers, :info),
    Kind.new(:container_stopped, :servers, :warning),
    Kind.new(:container_started, :servers, :info),
    Kind.new(:scheduled_task_failed, :servers, :warning),
    Kind.new(:scheduled_task_late, :servers, :warning),
    Kind.new(:vulnerability_found, :security, :warning),
    Kind.new(:vulnerability_feed_failed, :configuration, :warning),
    Kind.new(:container_unhealthy, :servers, :warning),
    Kind.new(:container_restarting, :servers, :warning),
    Kind.new(:image_update_available, :servers, :info),
    Kind.new(:port_opened, :security, :warning),
    Kind.new(:port_closed, :security, :info),
    Kind.new(:ip_address_added, :servers, :info),
    Kind.new(:ip_address_removed, :servers, :info),
    Kind.new(:server_note_added, :servers, :info),
    Kind.new(:security_updates_available, :security, :warning),
    Kind.new(:server_created, :servers, :info),
    Kind.new(:server_updated, :servers, :info),
    Kind.new(:servers_imported, :servers, :info),
    Kind.new(:server_deleted, :servers, :warning),
    Kind.new(:server_group_created, :configuration, :info),
    Kind.new(:server_group_deleted, :configuration, :info),
    Kind.new(:user_invited, :configuration, :info),
    Kind.new(:invitation_accepted, :security, :warning),
    Kind.new(:invitation_revoked, :configuration, :info),
    Kind.new(:user_role_changed, :security, :warning),
    Kind.new(:user_deactivated, :security, :warning),
    Kind.new(:user_reactivated, :security, :warning),
    Kind.new(:user_locked, :security, :warning),
    Kind.new(:two_factor_enabled, :security, :info),
    Kind.new(:two_factor_disabled, :security, :critical),
    Kind.new(:two_factor_backup_code_used, :security, :warning),
    Kind.new(:public_key_created, :configuration, :info),
    Kind.new(:public_key_deleted, :configuration, :info),
    Kind.new(:ssh_key_generated, :security, :critical),
    Kind.new(:ssh_key_rotation_started, :security, :warning),
    Kind.new(:ssh_key_rotated, :security, :critical),
    Kind.new(:automation_run, :configuration, :info),
    Kind.new(:monitor_down, :servers, :critical),
    Kind.new(:monitor_up, :servers, :info),
    Kind.new(:monitor_cert_expiring, :security, :warning),
    Kind.new(:server_without_monitor, :servers, :warning),
    Kind.new(:ovh_service_expiring, :servers, :warning),
    Kind.new(:gandi_domain_expiring, :servers, :warning),
    Kind.new(:dns_record_outside_fleet, :security, :warning),
    Kind.new(:dns_record_conflict, :configuration, :info),
    Kind.new(:ovh_service_unmanaged, :servers, :info),
    Kind.new(:integration_enabled, :configuration, :info),
    Kind.new(:integration_disabled, :configuration, :info),
    Kind.new(:integration_sync_failed, :configuration, :warning),
    Kind.new(:coolify_backup_failed, :servers, :warning),
    Kind.new(:integration_connection_added, :configuration, :info),
    Kind.new(:integration_connection_removed, :configuration, :info)
  ].index_by(&:key).freeze

  belongs_to :user, optional: true
  belongs_to :server, optional: true
  belongs_to :public_key, optional: true

  validates :kind, inclusion: { in: KINDS.keys.map(&:to_s) }

  after_create_commit -> { NotifyActivityJob.perform_later(self) }

  scope :recent, -> { order(created_at: :desc, id: :desc) }
  scope :of_kind, ->(kind) { where(kind: kind.to_s) }
  scope :in_category, ->(category) { where(kind: KINDS.values.select { |kind| kind.category == category.to_sym }.map { |kind| kind.key.to_s }) }

  # Records an activity; the author defaults to the signed-in user (Current.user).
  def self.record!(kind, server: nil, public_key: nil, unix_user: nil, user: Current.user, **data)
    data[:server_name] ||= server&.name
    data[:public_key_name] ||= public_key&.name
    create!(kind: kind.to_s, server: server, public_key: public_key, unix_user: unix_user, user: user, data: data.compact)
  end

  def definition = KINDS.fetch(kind.to_sym)

  delegate :label, :category, :severity, to: :definition

  def self.category_label(category) = I18n.t("activity.categories.#{category}")

  def author_name = user&.email || I18n.t("activity.system")

  def server_name = server&.name || data["server_name"]

  def public_key_name = public_key&.name || data["public_key_name"]

  def key_name = data["key_name"] || I18n.t("activity.unnamed")

  # « web », or « web » (account root) for an account other than the login one.
  def target
    return unless server_name
    return I18n.t("activity.target", server_name: server_name) if unix_user.blank? || unix_user == (server&.username || unix_user)

    I18n.t("activity.target_account", server_name: server_name, account: unix_user)
  end

  # One-line description of what happened, in the reader's language (Activity::Summaries).
  def summary = instance_exec(&Summaries::BY_KIND.fetch(kind.to_sym))
end
