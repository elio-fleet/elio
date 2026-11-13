# Manual DNS: records typed in (pasted as CSV), for a DNS that has no
# extension. Each connection is one named source (its records:
# DnsRecord.source "manual:<connection id>"), in the DNS of the fleet like
# OVHcloud, Technitium or Gandi. Each save replaces the source's records;
# the "Test" button previews what would be read, without saving.
class Integrations::ManualDns < Integrations::Base
  self.key = "manual_dns"
  self.label = "DNS"
  self.icon = :globe
  self.default_interval = 1440

  SOURCE_PREFIX = "manual:"

  class << self
    def label = I18n.t("integrations.manual_dns.label")

    def connection_fields
      [ Integrations::Field.new(key: :records, label: I18n.t("integrations.manual_dns.records"), type: :textarea, required: true,
                                placeholder: "name,type,value,ttl\nwww.example.com,A,203.0.113.10,3600\nshop.example.com,CNAME,www.example.com",
                                hint: I18n.t("integrations.manual_dns.records_hint", count: Dns::CsvImport::MAX_LINES)) ]
    end

    def source(connection) = "#{SOURCE_PREFIX}#{connection.id}"

    # The preview: what the CSV gives, and every refused line with its reason.
    def test_connection(connection)
      result = Dns::CsvImport.parse(connection.value(:records))
      raise Integrations::Error, I18n.t("integrations.manual_dns.nothing") if result.rows.empty? && result.refused.empty?

      [ result.summary, *result.refused.first(20).map { |refusal| I18n.t("integrations.manual_dns.refused_line", line: refusal.line, reason: refusal.reason, text: refusal.text) },
        (I18n.t("integrations.manual_dns.more_refused", count: result.refused.size - 20) if result.refused.size > 20) ].compact.join("\n")
    end

    # Replaces the source's records (attached to the servers, health and
    # alerts like every source), logged when they change.
    def sync_connection(connection)
      raise Integrations::Error, I18n.t("integrations.manual_dns.unsaved") unless connection.persisted?

      result = Dns::CsvImport.parse(connection.value(:records))
      before = DnsRecord.of_source(source(connection)).pluck(:source_id).to_set
      Dns::Store.replace(source(connection), result.rows)
      after = DnsRecord.of_source(source(connection)).pluck(:source_id).to_set
      if before != after
        Activity.record!(:dns_manual_updated, user: Current.user, source: connection.label, count: after.size,
                                              added: (after - before).size, removed: (before - after).size)
      end
      connection.update_columns(state: connection.state.merge("records" => after.size, "refused" => result.refused.size))
      result.summary
    end

    # The source's records go with it.
    def connection_removed(connection) = Dns::Store.replace(source(connection), [])

    def connection_summary(connection)
      return unless connection.state["records"]

      I18n.t("integrations.manual_dns.connection_summary", count: connection.state["records"], refused: connection.state["refused"].to_i)
    end

    # The name of a manual source ("manual:12" → the connection's name).
    def source_label(source)
      id = source.to_s.delete_prefix(SOURCE_PREFIX)
      Current.manual_dns_labels ||= IntegrationConnection.joins(:integration).where(integrations: { kind: key }).to_h { |connection| [ connection.id.to_s, connection.label ] }
      Current.manual_dns_labels[id] || I18n.t("integrations.manual_dns.label")
    end

    def dns_source?(_integration) = true

    def help_partial = "integrations/manual_dns/help"
  end
end
