# The DNS alerts common to every source (AppSetting, Settings → Extensions →
# DNS), after each change of the DNS of the fleet: a record pointing to an IP
# outside the fleet (dns_record_outside_fleet) and, optionally, a name whose
# records differ between sources (dns_record_conflict). Each one once, until
# it goes away. Nothing for a source's first records (everything would be
# new: enabling a second source must not flood the activity), and a record
# already known through another source is not new.
module Dns::Alerts
  def self.call(settings = AppSetting.current)
    state = settings.dns_alert_state.dup
    known = known_outside(state)
    current = DnsRecord.outside_fleet.pluck(:source, :name, :value).group_by(&:first).transform_values { |rows| rows.map { |_, name, value| "#{name} #{value}" }.uniq.sort }
    known_anywhere = known.values.flatten.to_set
    first_run = current.keys.select { |source| known[source].nil? }

    (current.keys - first_run).each do |source|
      (current[source] - known[source] - known_anywhere.to_a).each do |key|
        name, value = key.split(" ", 2)
        Activity.record!(:dns_record_outside_fleet, user: nil, record: name, target: value) if settings.dns_alert_outside
        known_anywhere << key
      end
    end
    sources = DnsRecord.distinct.pluck(:source)
    state["outside"] = (sources | known.keys).index_with { |source| current.fetch(source, []) }

    conflicts = DnsRecord.conflicting_names.sort
    # A source seen for the first time brings its conflicts along: recorded, not logged.
    unless state["conflicts"].nil? || first_run.any? || (sources - known.keys).any?
      (conflicts - state["conflicts"]).each do |name|
        labels = DnsRecord.where(name: name).distinct.order(:source).pluck(:source).map { |source| DnsRecord.source_label(source) }
        Activity.record!(:dns_record_conflict, user: nil, record: name, sources: labels) if settings.dns_alert_conflict
      end
    end
    state["conflicts"] = conflicts

    settings.update_columns(dns_alert_state: state)
  end

  # { source => keys already seen } ({} on the very first run). A flat list
  # (written by the migration from the extensions' states) counts for every
  # source that has records.
  def self.known_outside(state)
    case state["outside"]
    when Hash then state["outside"]
    when Array then DnsRecord.distinct.pluck(:source).index_with { state["outside"] }
    else {}
    end
  end
  private_class_method :known_outside
end
