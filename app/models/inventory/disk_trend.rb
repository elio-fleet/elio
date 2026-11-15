# When the fullest disk of a server will be full at the pace of the last
# WINDOW: a least-squares line through its health samples, computed in SQL
# (regr_slope). Nothing when the disk is not filling up, when the history is
# too short to say, or when "full" is further than HORIZON_DAYS away.
class Inventory::DiskTrend
  WINDOW = 7.days
  MIN_SPAN = 1.day
  MIN_SAMPLES = 6
  HORIZON_DAYS = 90
  CRIT_DAYS = 7
  WARN_DAYS = 30

  def initialize(server, now: Time.current)
    @server = server
    @now = now
  end

  # Days until 100 %, nil when there is nothing to announce.
  def days_left
    return @days_left if defined?(@days_left)

    @days_left = compute
  end

  def full_on = days_left && (@now + days_left.days).to_date

  def tone
    return unless days_left

    if days_left <= CRIT_DAYS then :crit
    elsif days_left <= WARN_DAYS then :warn
    end
  end

  private

  def compute
    samples = @server.health_samples.where(collected_at: (@now - WINDOW)..@now)
    slope, count, first, last = samples.pick(Arel.sql("regr_slope(disk_percent, extract(epoch from collected_at))"), Arel.sql("regr_count(disk_percent, extract(epoch from collected_at))"),
                                             Arel.sql("min(collected_at)"), Arel.sql("max(collected_at)"))
    return unless slope && count >= MIN_SAMPLES && last - first >= MIN_SPAN

    per_day = slope * 1.day.to_i
    current = samples.where.not(disk_percent: nil).order(:collected_at).last&.disk_percent
    return unless per_day.positive? && current

    days = (100 - current) / per_day
    days.clamp(0, nil) if days <= HORIZON_DAYS
  end
end
