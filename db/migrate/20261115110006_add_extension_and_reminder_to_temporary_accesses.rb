# A temporary access can be extended (its expiry pushed back on the server) and
# its key owner reminded shortly before it ends: count the extensions for the
# server's history of accesses, and remember the reminder so it is sent once.
class AddExtensionAndReminderToTemporaryAccesses < ActiveRecord::Migration[8.1]
  def change
    add_column :temporary_accesses, :extensions_count, :integer, null: false, default: 0
    add_column :temporary_accesses, :expiry_reminded_at, :datetime
  end
end
