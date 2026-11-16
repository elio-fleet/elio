# Runs a block over items in parallel threads, at most `limit` at a time, and
# returns the results in the items' order. Meant for slow network work (SSH,
# TCP) on many servers. Each thread runs inside the Rails executor, so the
# block may use Active Record (one pooled connection per thread: keep `limit`
# within the database pool when it does).
#
# An exception in one item does not stop the others: once every item is done,
# the first exception is raised again.
module BoundedParallel
  DEFAULT_LIMIT = Elio::Env.integer("ELIO_PARALLEL_LIMIT")

  def self.map(items, limit: DEFAULT_LIMIT, &block)
    items = items.to_a
    return [] if items.empty?
    return items.map(&block) if limit <= 1 || items.one?

    queue = Queue.new
    items.each_with_index { |item, index| queue << [ item, index ] }
    queue.close

    results = Array.new(items.size)
    errors = Array.new(items.size)
    workers = Array.new([ limit, items.size ].min) do
      Thread.new do
        while (item, index = queue.pop)
          Rails.application.executor.wrap do
            results[index] = block.call(item)
          rescue StandardError => e
            errors[index] = e
          end
        end
      end
    end
    workers.each(&:join)

    first_error = errors.compact.first
    raise first_error if first_error

    results
  end

  def self.each(items, **options, &block)
    map(items, **options, &block)
    nil
  end
end
