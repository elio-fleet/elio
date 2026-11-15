# Scheduling options of an automation: hours it may start in (e.g. the
# packages inventory at night only; both nil = at any time), server groups it
# leaves out, and the durations of its last runs (seconds, newest last).
class AddSchedulingOptionsToAutomations < ActiveRecord::Migration[8.1]
  def change
    add_column :automations, :window_start_hour, :integer
    add_column :automations, :window_end_hour, :integer
    add_column :automations, :excluded_server_group_ids, :jsonb, default: [], null: false
    add_column :automations, :run_durations, :jsonb, default: [], null: false
  end
end
