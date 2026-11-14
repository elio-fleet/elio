# A failing channel waits longer and longer between attempts (instead of every
# notification retrying on its own), and is turned off after failing for a
# long time: the channel remembers how many attempts failed in a row, since
# when, and when the next attempt may happen.
class AddBackoffToNotificationChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :notification_channels, :failure_count, :integer, default: 0, null: false
    add_column :notification_channels, :failing_since, :datetime
    add_column :notification_channels, :retry_at, :datetime
  end
end
