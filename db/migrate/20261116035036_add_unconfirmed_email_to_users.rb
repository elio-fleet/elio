# A new email address chosen in My account is kept here until its owner
# follows the link sent to it: the address of an account is where its password
# can be reset, so it only changes once proved to be theirs.
class AddUnconfirmedEmailToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :unconfirmed_email, :string
  end
end
