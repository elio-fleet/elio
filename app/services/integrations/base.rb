# Definition of an extension (see Integration): its form fields, connection
# test, synchronization, and what it adds to the interface. Subclasses set
# the class attributes and override the hooks they need.
class Integrations::Base
  Field = Integrations::Field

  class_attribute :key, :label, :description, :icon, :default_interval, instance_writer: false

  # The description of an extension, in the reader's language
  # (integrations.<key>.description), unless the class sets one.
  class << self
    alias_method :set_description, :description
    def description = set_description || I18n.t("integrations.#{key}.description")
  end
  self.icon = :bolt
  self.default_interval = 360

  class << self
    def fields = []

    # Raises Integrations::Error with a readable message; returns what was found ("12 sondes").
    def test_connection(_integration) = raise(NotImplementedError)

    # Reads the external service and stores what it found; returns a summary.
    def sync(_integration) = raise(NotImplementedError)

    # Tabs added to the server page: [{ key:, label:, count: ->(server) {}, tone: ->(server) {},
    # visible: ->(server) {} }] (tone and visible optional), rendered with the partial
    # "integrations/<key>/server_tab".
    def server_tabs = []

    # Links added to the sidebar: [{ label:, path: (helper name), icon: }].
    def sidebar_links = []

    # Health reasons of a server (HealthStatus::Reason), when the extension raises alerts.
    def health_reasons(_integration, _server) = []

    # Help shown on the settings page (partial "integrations/<key>/help"), or nil.
    def help_partial = nil

    # Does this extension feed the DNS of the fleet (DnsRecord, Dns)?
    def dns_source?(_integration) = false

    # SSH keys the service puts on servers (Coolify's key): { fingerprint =>
    # { "source" => "Coolify", "name" => …, "detail" => … } }. They are not
    # "outside the keyring" (no unknown-key alert) and are named in the keys tab.
    def known_keys(_integration) = {}

    # Several connections (IntegrationConnection): the fields of ONE
    # connection (URL, token…). Empty = a single connection, in `fields`.
    # With connections, `fields` keeps what they share (alerts), and
    # `test_connection` / `sync_connection` receive an IntegrationConnection.
    def connection_fields = []

    def multiple_connections? = connection_fields.any?

    # Reads the service for one connection and stores what it found; returns a summary.
    def sync_connection(_connection) = raise(NotImplementedError)

    # After every connection was synchronized (at least one succeeded).
    def after_connections_sync(_integration) = nil

    # The name of a connection read from the service (a team), and the
    # heading connections are grouped under (an instance); nil when none.
    def connection_label(_connection) = nil
    def connection_group(_connection) = nil

    # One line under a connection in the settings ("6 servers · Coolify v4.6.0"), or nil.
    def connection_summary(_connection) = nil
  end
end
