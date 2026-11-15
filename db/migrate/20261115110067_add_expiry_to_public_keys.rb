# A keyring key can be given an expiry date (a laptop or a contractor's key to
# rotate, a yearly policy): remember the date, and when the rotation reminder
# was recorded so it is sent once per date.
class AddExpiryToPublicKeys < ActiveRecord::Migration[8.1]
  def change
    add_column :public_keys, :expires_on, :date
    add_column :public_keys, :expiry_reminded_at, :datetime
  end
end
