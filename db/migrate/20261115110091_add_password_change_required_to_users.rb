# An admin can ask someone to choose a new password (an account that may
# have been exposed): until they do, every page leads to "My account".
class AddPasswordChangeRequiredToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_change_required, :boolean, null: false, default: false
  end
end
