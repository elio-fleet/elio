require "csv"

# The Journal's events for an audit, with the filters of the page: what the
# page shows (date, kind, severity, summary, server, author, key, account)
# and the event's permanent link, never the raw data. Column names are
# stable English keys, the same in CSV and JSON; the kind label and the
# summary are in the reader's language. At most MAX_ROWS events (the most
# recent): the JSON says when the export was cut.
#
#   ActivityExport.new(Activity.recent.at_least(:warning), filters: { severity: "warning" }, url: ->(activity) { … }).to_csv
class ActivityExport
  MAX_ROWS = 50_000
  BATCH = 1_000
  HEADERS = %w[id created_at kind label category severity summary server author unix_user public_key url].freeze

  # `scope`: a relation of Activity, in the page's order; `url`: the permanent link of an activity.
  def initialize(scope, filters: {}, url: nil, limit: MAX_ROWS)
    @scope = scope
    @limit = limit
    @filters = filters.compact_blank
    @url = url
  end

  def records
    @records ||= ids.first(@limit).each_slice(BATCH).flat_map do |slice|
      by_id = Activity.where(id: slice).includes(:user, :server, :public_key).index_by(&:id)
      slice.filter_map { |id| by_id[id] }.map { |activity| record(activity) }
    end
  end

  def truncated? = ids.size > @limit

  def to_csv
    CSV.generate do |csv|
      csv << HEADERS
      records.each { |record| csv << HEADERS.map { |key| CsvCell.safe(record[key]) } }
    end
  end

  def to_json(*)
    { generated_at: Time.current.iso8601, filters: @filters, count: records.size, truncated: truncated?, events: records }.to_json
  end

  def filename(extension) = "elio-journal-#{Date.current.iso8601}.#{extension}"

  private

  # The ids first (one light query, one more than kept to know if it was cut), the records by batches of BATCH.
  def ids = @ids ||= @scope.except(:includes, :preload).limit(@limit + 1).pluck(:id)

  def record(activity)
    { "id" => activity.id, "created_at" => activity.created_at.iso8601, "kind" => activity.kind, "label" => activity.label,
      "category" => activity.category.to_s, "severity" => activity.severity.to_s, "summary" => activity.summary,
      "server" => activity.server_name, "author" => activity.user&.email, "unix_user" => activity.unix_user,
      "public_key" => activity.public_key_name, "url" => @url&.call(activity) }
  end
end
