class ActivitiesController < ApplicationController
  PER_PAGE = 50

  def index
    @category = params[:category].presence_in(Activity::CATEGORIES.map(&:to_s))
    @server = Server.find_by(id: params[:server_id])
    # One kind (the link of a grouped notification).
    @kind = params[:kind].presence_in(Activity::KINDS.keys.map(&:to_s))

    scope = Activity.recent.includes(:user, :server, :public_key)
    scope = scope.in_category(@category) if @category
    scope = scope.where(server: @server) if @server
    scope = scope.of_kind(@kind) if @kind
    @pager = paginate(scope, per_page: PER_PAGE)
    @activities = @pager.records
  end
end
