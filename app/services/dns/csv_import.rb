require "csv"
require "ipaddr"

# The records of a manual DNS source (Integrations::ManualDns), pasted as CSV:
#
#   name,type,value[,ttl[,zone]]
#   www.example.com,A,203.0.113.10,3600
#   shop.example.com;CNAME;www.example.com
#
# One record per line; "," ";" or a tab between the columns; an optional
# header line names the columns (any order: name, type, value, ttl, zone).
# Types: A, AAAA, CNAME (the ones the fleet's DNS reads). The zone is the
# `zone` column, else the last two labels of the name. Blank lines and lines
# starting with # are skipped; the other lines that cannot be read are
# refused with their reason, never stored.
#
#   result = Dns::CsvImport.parse(text)
#   result.rows    # [{ zone:, name:, record_type:, value:, ttl: }] for Dns::Store.replace
#   result.refused # [Refusal(line:, text:, reason:)]
module Dns::CsvImport
  COLUMNS = %w[name type value ttl zone].freeze
  MAX_LINES = 20_000
  LABEL = /\A(\*|[a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9_])?)\z/i

  Refusal = Data.define(:line, :text, :reason)
  Result = Data.define(:rows, :refused) do
    def summary = I18n.t("dns.csv_import.summary", count: rows.size, refused: refused.size)
  end

  def self.parse(text)
    rows, refused, seen = [], [], Set.new
    columns = COLUMNS
    lines = text.to_s.each_line.first(MAX_LINES)
    header_line = first_line(lines)
    lines.each.with_index(1) do |raw, number|
      line = raw.strip
      next if line.empty? || line.start_with?("#")

      cells = cells(line)
      if number == header_line && header?(cells)
        columns = cells.map(&:downcase)
        next
      end

      record = columns.zip(cells).to_h
      reason = invalid_reason(record)
      row = reason ? nil : row_for(record)
      reason ||= :duplicate unless row.nil? || seen.add?(row.values_at(:name, :record_type, :value))
      reason ? refused << Refusal.new(line: number, text: line.truncate(120), reason: I18n.t("dns.csv_import.reasons.#{reason}")) : rows << row
    end
    refused << Refusal.new(line: MAX_LINES + 1, text: "", reason: I18n.t("dns.csv_import.reasons.too_long", count: MAX_LINES)) if text.to_s.lines.size > MAX_LINES
    Result.new(rows: rows, refused: refused)
  end

  def self.cells(line)
    separator = [ "\t", ";", "," ].max_by { |candidate| line.count(candidate) }
    CSV.parse_line(line, col_sep: separator).to_a.map { |cell| cell.to_s.strip }
  rescue CSV::MalformedCSVError
    line.split(/[\t;,]/).map(&:strip)
  end

  def self.first_line(lines) = lines.index { |line| line.strip.present? && !line.strip.start_with?("#") }.to_i + 1

  def self.header?(cells) = cells.map(&:downcase).include?("name") && cells.map(&:downcase).include?("type")

  def self.invalid_reason(record)
    name = clean(record["name"])
    type = record["type"].to_s.upcase
    value = record["type"].to_s.casecmp?("CNAME") ? clean(record["value"]) : record["value"].to_s.strip
    return :columns if name.empty? || type.empty? || value.empty?
    return :type unless DnsRecord::TYPES.include?(type)
    return :name unless hostname?(name)
    return :ttl if record["ttl"].present? && !record["ttl"].to_s.match?(/\A\d{1,9}\z/)
    return :zone if record["zone"].present? && !(hostname?(clean(record["zone"])) && (name == clean(record["zone"]) || name.end_with?(".#{clean(record["zone"])}")))

    case type
    when "A" then :ipv4 unless ip?(value, :ipv4?)
    when "AAAA" then :ipv6 unless ip?(value, :ipv6?)
    when "CNAME" then :cname unless hostname?(value)
    end
  end

  def self.row_for(record)
    name = clean(record["name"])
    type = record["type"].to_s.upcase
    value = type == "CNAME" ? clean(record["value"]) : IPAddr.new(record["value"].to_s.strip).to_s
    zone = record["zone"].present? ? clean(record["zone"]) : name.split(".").last(2).join(".")
    { zone: zone, name: name, record_type: type, value: value, ttl: record["ttl"].presence&.to_i }
  end

  def self.clean(value) = value.to_s.strip.downcase.chomp(".")

  def self.hostname?(value) = value.length <= 253 && value.include?(".") && value.split(".", -1).all? { |label| label.match?(LABEL) }

  def self.ip?(value, family)
    IPAddr.new(value).public_send(family) && !value.include?("/")
  rescue IPAddr::Error
    false
  end
end
