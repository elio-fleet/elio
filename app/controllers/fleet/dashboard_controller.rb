class DashboardController < ApplicationController
  # Overview: setup checklist (alone while the fleet is empty), fleet
  # figures, what needs attention by gravity, recent activity, the groups and
  # the temporary accesses in progress.
  def index
    @checklist = OnboardingChecklist.new
    @servers = Server.order(:name).includes(:inventory_snapshots, :server_groups).to_a
    @summary = FleetSummary.new(@servers)
    @insights = KeyInsights.new
    @attention = AttentionList.new(@servers, insights: @insights, summary: @summary)
    @temporary_accesses = TemporaryAccess.active.includes(:server, :public_key).order(:expires_at)
    @vulnerabilities = SidebarCounts.new.vulnerabilities
    @groups = ServerGroup.order(:name).to_a
    @activities = Activity.recent.includes(:user, :server, :public_key).limit(8)
  end
end
