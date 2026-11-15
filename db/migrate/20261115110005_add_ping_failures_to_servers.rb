# A server is declared unreachable (server_unreachable logged) only after
# consecutive failed pings, and only if it was ever seen answering: a server
# just added with a wrong port, or a single lost packet, no longer fills the
# journal. ping_failures counts the failures in a row, last_reachable_at is
# the last time its SSH port answered.
class AddPingFailuresToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :ping_failures, :integer, null: false, default: 0
    add_column :servers, :last_reachable_at, :datetime

    reversible do |direction|
      direction.up do
        # Online servers: seen answering at their last check.
        execute "UPDATE servers SET last_reachable_at = last_checked_at WHERE reachable = true"
        # Servers already declared down keep their state, so that coming back
        # logs server_back_online when their server_unreachable was logged.
        execute <<~SQL
          UPDATE servers SET ping_failures = 2,
                 last_reachable_at = (SELECT max(activities.created_at) FROM activities
                                      WHERE activities.server_id = servers.id AND activities.kind = 'server_unreachable')
          WHERE reachable = false
        SQL
      end
    end
  end
end
