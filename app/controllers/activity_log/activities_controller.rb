# The Journal's events: filtered by category, minimum severity, kind and
# server (all kept in the URL, combined with the text and period search),
# exported as .csv / .json for an audit with the same filters, and one
# event on its own page (a permanent link).
class ActivitiesController < ApplicationController
  PER_PAGE = 50

  def index
    read_filters
    scope = Activity.recent.includes(:user, :server, :public_key)
    scope = scope.in_category(@category) if @category
    scope = scope.at_least(@severity) if @severity
    scope = scope.where(server: @server) if @server
    scope = scope.of_kind(@kind) if @kind
    @search = JournalSearch.new(params)
    scope = @search.apply(scope, Activity)
    respond_to do |format|
      format.html do
        @pager = paginate(scope, per_page: PER_PAGE)
        @activities = @pager.records
      end
      format.csv { export(scope, :csv) }
      format.json { export(scope, :json) }
    end
  end

  def show
    @activity = Activity.includes(:user, :server, :public_key).find(params[:id])
  end

  private

  def read_filters
    @category = params[:category].presence_in(Activity::CATEGORIES.map(&:to_s))
    @severity = params[:severity].presence_in(Activity::SEVERITIES.excluding(:info).map(&:to_s))
    @server = Server.find_by(id: params[:server_id])
    # One kind (the select, or the link of a grouped notification).
    @kind = params[:kind].presence_in(Activity::KINDS.keys.map(&:to_s))
    @filters = { category: @category, severity: @severity, kind: @kind, server_id: @server&.id }.compact
  end

  def export(scope, format)
    filters = @filters.except(:server_id).merge(server: @server&.name, **@search.to_params)
    export = ActivityExport.new(scope, filters: filters, url: ->(activity) { activity_url(activity) })
    send_data format == :csv ? export.to_csv : export.to_json, filename: export.filename(format), type: format, disposition: "attachment"
  end
end
