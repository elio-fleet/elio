# What the Journal is searched with (both tabs): a text and a period, read
# from the query parameters, kept in the links (filters, pagination).
#
#   search = JournalSearch.new(params)
#   scope = search.apply(Activity.recent, Activity) # text and dates
class JournalSearch
  MAX_LENGTH = 100

  attr_reader :text, :from, :to

  def initialize(params)
    @text = params[:q].to_s.squish.first(MAX_LENGTH).presence
    @from = date(params[:from])
    @to = date(params[:to])
    @from, @to = @to, @from if @from && @to && @from > @to
  end

  def any? = [ text, from, to ].any?

  # The query parameters to keep in a link.
  def to_params = { q: text, from: from&.iso8601, to: to&.iso8601 }.compact

  # `model` answers `search(text)`; the dates filter its created_at, in the
  # application's time zone.
  def apply(scope, model)
    scope = scope.merge(model.search(text)) if text
    scope = scope.where(model.table_name => { created_at: from.in_time_zone.beginning_of_day.. }) if from
    scope = scope.where(model.table_name => { created_at: ..to.in_time_zone.end_of_day }) if to
    scope
  end

  def self.like(text) = "%#{ActiveRecord::Base.sanitize_sql_like(text)}%"

  private

  def date(value)
    Date.iso8601(value.to_s) if value.present?
  rescue Date::Error
    nil
  end
end
