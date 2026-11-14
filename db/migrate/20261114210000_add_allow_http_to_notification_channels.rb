# A webhook on the internal network may answer over plain HTTP: allowed per
# channel, on purpose, by the administrator who creates it (off by default).
class AddAllowHttpToNotificationChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :notification_channels, :allow_http, :boolean, default: false, null: false
  end
end
