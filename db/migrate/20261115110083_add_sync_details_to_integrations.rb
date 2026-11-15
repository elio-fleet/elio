# The settings show how long the last sync of an extension took, and when
# its API key expires (read from the service when it says so), with an alert
# logged once before it does.
class AddSyncDetailsToIntegrations < ActiveRecord::Migration[8.1]
  def change
    add_column :integrations, :last_sync_duration_ms, :integer
    add_column :integrations, :credential_expires_at, :datetime
    add_column :integrations, :credential_expiry_logged, :boolean, null: false, default: false
  end
end
