# "Tâches": the background tasks (inventories, keys scans, automation runs)
# with their status, and what is coming (queued tasks, next automations).
# Visible to every role; the queue's technical view is /jobs (admins).
class TasksController < ApplicationController
  PER_PAGE = 50

  def index
    @filter = params[:status].presence_in(BackgroundTask::FILTERS.keys)
    @search = JournalSearch.new(params)
    @pager = paginate(@search.apply(BackgroundTask.filtered(@filter).recent.includes(:user), BackgroundTask), per_page: PER_PAGE)
    @tasks = @pager.records
    @counts = BackgroundTask.group(:status).count
    @upcoming_automations = Automation.where(enabled: true).select(&:available?).sort_by(&:next_run_at)
    @workers_running = JobWorkers.running?
  end

  def show
    @task = BackgroundTask.find(params[:id])
    @items = @task.items.includes(:server)
    @workers_running = JobWorkers.running? if @task.unfinished?
  end
end
