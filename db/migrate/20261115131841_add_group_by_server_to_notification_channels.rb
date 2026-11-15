# A channel may group its notifications by server as well as by kind: a batch
# then remembers its server, and the open batch is unique per channel, kind
# and server (COALESCE: batches without a server share one key, as before).
class AddGroupByServerToNotificationChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :notification_channels, :group_by_server, :boolean, null: false, default: false
    add_column :notification_batches, :server_id, :bigint

    remove_index :notification_batches, [ :notification_channel_id, :kind ], name: "index_notification_batches_open", unique: true, where: "(closed_at IS NULL)"
    add_index :notification_batches, "notification_channel_id, kind, COALESCE(server_id, 0)", name: "index_notification_batches_open", unique: true, where: "(closed_at IS NULL)"
  end
end
