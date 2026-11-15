# "Tâches": the background tasks (inventories, keys scans, automation runs)
# with their status, and what is coming (queued tasks, next automations).
# Visible to every role; the queue's technical view is /jobs (admins).
class TasksController < ApplicationController
  PER_PAGE = 50

  def index
    @filter = params[:status].presence_in(BackgroundTask::FILTERS.keys)
    @kind = params[:kind].presence_in(BackgroundTask::KINDS)
    @search = JournalSearch.new(params)
    @pager = paginate(@search.apply(BackgroundTask.filtered(@filter).of_kind(@kind).recent.includes(:user), BackgroundTask), per_page: PER_PAGE)
    @tasks = @pager.records
    @counts = BackgroundTask.of_kind(@kind).group(:status).count
    @kinds = BackgroundTask::KINDS & BackgroundTask.distinct.pluck(:kind)
    @upcoming_automations = Automation.where(enabled: true).select(&:available?).sort_by(&:next_run_at)
    @workers_running = JobWorkers.running?
  end

  def show
    @task = BackgroundTask.find(params[:id])
    # Slowest first on demand (finished servers by duration, then the others).
    @sort = params[:sort].presence_in(%w[duration])
    @items = @task.items.includes(:server).to_a
    @items = @items.sort_by { |item| [ item.duration ? 0 : 1, -item.duration.to_f, item.server_name ] } if @sort
    @slow_ids = @task.slow_item_ids(@items)
    @workers_running = JobWorkers.running? if @task.unfinished?
  end
end
