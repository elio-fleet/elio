# The display choices of each user that follow them from one browser to
# another (first: the columns hidden in the fleet list).
class AddPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :preferences, :jsonb, default: {}, null: false
  end
end
