# The owner of a keyring key ("my key"): a person's key used by "Add my key
# temporarily". A key has one owner at most; deleting the user keeps the key.
class AddUserToPublicKeys < ActiveRecord::Migration[8.1]
  def change
    add_reference :public_keys, :user, null: true, index: true, foreign_key: { on_delete: :nullify }
  end
end
