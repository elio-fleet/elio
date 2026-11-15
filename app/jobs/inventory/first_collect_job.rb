# Collects the first inventory of a server just added (ServersController#create),
# so its page fills in without a click. Only when Elio can already log in: a
# server whose key is not installed yet keeps an empty inventory instead of
# failed categories (its page tells how to install the key).
class Inventory::FirstCollectJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(server)
    return if server.inventoried_at

    result = Ssh::Check.call(server)
    server.record_ssh_status!(false) if result.reason == :key_refused
    Inventory::Collection.call(server) if result.success?
  end
end
