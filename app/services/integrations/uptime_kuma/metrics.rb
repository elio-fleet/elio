# Reads the Prometheus /metrics page of Uptime Kuma (1.x and 2.x) into one
# Monitor per probe: identity (name, type, target), tags, status, response
# times, uptime ratios per window and certificate. Lines of other metrics
# (process_*, nodejs_*…) are ignored.
module Integrations::UptimeKuma::Metrics
  Monitor = Data.define(:id, :name, :monitor_type, :url, :hostname, :port, :tags, :status, :response_time_ms, :uptime, :average_response_ms,
                        :cert_days_remaining, :cert_valid)

  Result = Data.define(:monitors, :version)

  LINE = /\A(?<name>[a-zA-Z_:][a-zA-Z0-9_:]*)(?:\{(?<labels>.*)\})?\s+(?<value>\S+)(?:\s+\d+)?\s*\z/
  LABEL = /(?<key>[a-zA-Z_][a-zA-Z0-9_]*)="(?<value>(?:[^"\\]|\\.)*)"\s*,?/
  IDENTITY = %w[monitor_id monitor_name monitor_type monitor_url monitor_hostname monitor_port window].freeze

  def self.parse(text)
    monitors = {}
    version = nil

    text.to_s.each_line do |line|
      line = line.strip
      next if line.empty? || line.start_with?("#")

      match = LINE.match(line) or next
      labels = parse_labels(match[:labels].to_s)
      value = parse_value(match[:value])

      if match[:name] == "app_version"
        version = labels["version"]
        next
      end
      next unless match[:name].start_with?("monitor_") && (id = monitor_key(labels))

      monitor = monitors[id] ||= new_monitor(labels, id)
      window = labels["window"]
      case match[:name]
      when "monitor_status" then monitor[:status] = value&.to_i
      when "monitor_response_time" then monitor[:response_time_ms] = (value if value.nil? || value >= 0)
      when "monitor_response_time_seconds" then (monitor[:average_response_ms][window] = value && (value * 1000).round(3)) if window
      when "monitor_uptime_ratio" then (monitor[:uptime][window] = value) if window
      when "monitor_cert_days_remaining" then monitor[:cert_days_remaining] = value&.to_i
      when "monitor_cert_is_valid" then monitor[:cert_valid] = value.nil? ? nil : value == 1
      end
    end

    Result.new(monitors: monitors.values.map { |attributes| Monitor.new(**attributes) }.sort_by { |monitor| monitor.name.to_s.downcase }, version: version)
  end

  def self.parse_labels(text)
    text.scan(LABEL).to_h { |key, value| [ key, value.gsub(/\\(.)/) { $1 == "n" ? "\n" : $1 } ] }
  end
  private_class_method :parse_labels

  # "1", "0.99", "NaN", "+Inf" → a number, nil when it is not one.
  def self.parse_value(text)
    number = Float(text)
    number.nan? || number.infinite? ? nil : number
  rescue ArgumentError
    nil
  end
  private_class_method :parse_value

  # Uptime Kuma 2.x labels every series with monitor_id; 1.x has no id, its
  # series are told apart by the monitor's name.
  def self.monitor_key(labels)
    labels["monitor_id"].presence || (name = labels["monitor_name"].presence) && "name:#{name}"
  end
  private_class_method :monitor_key

  def self.new_monitor(labels, id)
    {
      id: id, name: labels["monitor_name"], monitor_type: labels["monitor_type"],
      url: url_with_host(labels["monitor_url"]), hostname: present(labels["monitor_hostname"]), port: present(labels["monitor_port"])&.to_i,
      tags: labels.keys - IDENTITY, status: nil, response_time_ms: nil, uptime: {}, average_response_ms: {}, cert_days_remaining: nil, cert_valid: nil
    }
  end
  private_class_method :new_monitor

  # Uptime Kuma writes "null" for an empty value.
  def self.present(value) = value == "null" ? nil : value.presence
  private_class_method :present

  # "https://" (ping probes) is not a target.
  def self.url_with_host(value)
    value = present(value)
    value if value && URI.parse(value).host.present?
  rescue URI::InvalidURIError
    nil
  end
  private_class_method :url_with_host
end
