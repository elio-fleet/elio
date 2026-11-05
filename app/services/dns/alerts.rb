# The DNS alerts common to every source (AppSetting, Settings → Extensions →
# DNS), after each change of the DNS of the fleet: a record pointing to an IP
# outside the fleet (dns_record_outside_fleet) and, optionally, a name whose
# records differ between sources (dns_record_conflict). Each one once, until
# it goes away; nothing on the first run (everything would be new).
module Dns::Alerts
  def self.call(settings = AppSetting.current)
    state = settings.dns_alert_state.dup

    outside = DnsRecord.outside_fleet.order(:name, :value).to_a
    once(state, "outside", outside.map { |record| "#{record.name} #{record.value}" }.uniq) do |key|
      name, value = key.split(" ", 2)
      Activity.record!(:dns_record_outside_fleet, user: nil, record: name, target: value) if settings.dns_alert_outside
    end

    conflicts = DnsRecord.conflicting_names.sort
    once(state, "conflicts", conflicts) do |name|
      sources = DnsRecord.where(name: name).distinct.order(:source).pluck(:source).map { |source| DnsRecord.source_label(source) }
      Activity.record!(:dns_record_conflict, user: nil, record: name, sources: sources) if settings.dns_alert_conflict
    end

    settings.update_columns(dns_alert_state: state)
  end

  # Yields the keys that were not there at the previous run (none on the first one).
  def self.once(state, name, keys)
    known = state[name]
    (keys - Array(known)).each { |key| yield key } unless known.nil?
    state[name] = keys
  end
  private_class_method :once
end
