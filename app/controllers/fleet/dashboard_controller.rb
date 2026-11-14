class DashboardController < ApplicationController
  # Failed (or partly failed) runs shown on the overview: the last day's.
  FAILED_TASKS_SINCE = 24.hours
  FAILED_TASKS_SHOWN = 3

  # Overview: setup checklist (alone while the fleet is empty), fleet
  # figures, what needs attention by gravity, recent activity, the failed
  # runs, the groups and the temporary accesses in progress.
  def index
    @checklist = OnboardingChecklist.new
    @servers = Server.order(:name).includes(:inventory_snapshots, :server_groups).to_a
    @summary = FleetSummary.new(@servers)
    @insights = KeyInsights.new
    @attention = AttentionList.new(@servers, insights: @insights, summary: @summary)
    @temporary_accesses = TemporaryAccess.active.includes(:server, :public_key).order(:expires_at)
    @vulnerabilities = SidebarCounts.new.vulnerabilities
    @vulnerability_change = vulnerability_change
    @groups = GroupOverview.new(ServerGroup.order(:name).to_a, @servers)
    @failed_tasks = BackgroundTask.failed_since(FAILED_TASKS_SINCE.ago).recent.limit(FAILED_TASKS_SHOWN).to_a
    @failed_tasks_count = BackgroundTask.failed_since(FAILED_TASKS_SINCE.ago).count if @failed_tasks.any?
    @activities = Activity.recent.includes(:user, :server, :public_key).limit(8)
  end

  private

  # Serious fixable CVEs now compared with a week ago (nil: no count then, or alerts off).
  def vulnerability_change
    severity = AppSetting.current.vulnerability_alert_severity
    VulnerabilityCount.weekly_change(@vulnerabilities&.value || 0, severity: severity) unless severity == "none"
  end
end
