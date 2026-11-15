# A server's health history over one of PERIODS, averaged in SQL per bucket
# so a 30-day chart stays a few hundred points whatever the collection
# interval. Read by the overview tab of a server (sparklines and charts).
class Inventory::HealthHistory
  Period = Data.define(:key, :span, :bucket)

  PERIODS = [
    Period.new(key: "24h", span: 24.hours, bucket: 5.minutes),
    Period.new(key: "7d", span: 7.days, bucket: 1.hour),
    Period.new(key: "30d", span: 30.days, bucket: 6.hours)
  ].index_by(&:key).freeze
  DEFAULT = "24h"

  attr_reader :period, :to

  def self.period_label(key) = I18n.t("inventory.health_history.periods.#{key}")

  def initialize(server, period: DEFAULT, now: Time.current)
    @server = server
    @period = PERIODS.fetch(period.to_s) { PERIODS.fetch(DEFAULT) }
    @to = now
  end

  def from = to - period.span

  # [[time, load %, memory %, disk %], …], oldest first: one point per
  # bucket, at its last measure (the newest point is the latest measure).
  def points
    @points ||= begin
      seconds = period.bucket.to_i
      bucket = Arel.sql("floor(extract(epoch from collected_at) / #{seconds})")
      @server.health_samples.where(collected_at: from..to).group(bucket).order(bucket)
             .pluck(Arel.sql("max(collected_at)"), Arel.sql("avg(load_percent)"), Arel.sql("avg(memory_percent)"), Arel.sql("avg(disk_percent)"))
             .map { |time, *values| [ time, *values.map { |value| value&.to_f } ] }
    end
  end
end
