# Health thresholds of their own for a server or a group of servers (a stricter
# production), separate thresholds for the inodes (until now those of the
# disk, copied so that nothing changes) and the swap (not watched until set),
# and how long a load or memory reading must stay above its threshold before
# it counts (0: at once, as before).
class AddHealthThresholdOverrides < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :health_thresholds, :jsonb, default: {}, null: false
    add_column :server_groups, :health_thresholds, :jsonb, default: {}, null: false

    add_column :app_settings, :health_inodes_warn, :integer, default: 80, null: false
    add_column :app_settings, :health_inodes_crit, :integer, default: 90, null: false
    add_column :app_settings, :health_swap_warn, :integer
    add_column :app_settings, :health_swap_crit, :integer
    add_column :app_settings, :health_sustained_minutes, :integer, default: 0, null: false

    reversible do |direction|
      direction.up { execute "UPDATE app_settings SET health_inodes_warn = health_disk_warn, health_inodes_crit = health_disk_crit" }
    end
  end
end
