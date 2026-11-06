# Notifications grouped by channel and kind (phase 13.7): the non-critical
# activities wait `group_minutes` and leave as one message. A batch is open
# (activities are added) until its delivery job closes it, then delivered or
# failed.
class CreateNotificationBatches < ActiveRecord::Migration[8.1]
  def change
    add_column :notification_channels, :group_minutes, :integer, null: false, default: 10

    create_table :notification_batches do |t|
      t.references :notification_channel, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.bigint :activity_ids, array: true, null: false, default: []
      t.datetime :send_at, null: false
      t.datetime :closed_at
      t.datetime :delivered_at
      t.datetime :failed_at
      t.timestamps
    end
    # One open batch per channel and kind.
    add_index :notification_batches, %i[notification_channel_id kind], unique: true, where: "closed_at IS NULL", name: "index_notification_batches_open"
    add_index :notification_batches, :send_at, where: "delivered_at IS NULL AND failed_at IS NULL", name: "index_notification_batches_undelivered"
  end
end
