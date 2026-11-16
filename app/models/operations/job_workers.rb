# Is a Solid Queue worker running? Without one, the tasks stay "à venir"
# forever (what happened in development before Solid Queue ran in Puma).
# nil when it cannot be known (another queue adapter, queue database absent).
module JobWorkers
  HEARTBEAT = 5.minutes

  def self.running?
    return unless solid_queue?

    SolidQueue::Process.where(kind: "Worker").where(last_heartbeat_at: HEARTBEAT.ago..).exists?
  rescue ActiveRecord::ActiveRecordError
    nil
  end

  # When a job of this class last finished (Solid Queue keeps the finished
  # jobs a day), nil if none did; :unknown when it cannot be known.
  def self.last_finished_at(class_name)
    return :unknown unless solid_queue?

    SolidQueue::Job.where(class_name: class_name).maximum(:finished_at)
  rescue ActiveRecord::ActiveRecordError
    :unknown
  end

  def self.solid_queue? = ActiveJob::Base.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
end
