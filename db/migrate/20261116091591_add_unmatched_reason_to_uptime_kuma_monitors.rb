# Why a probe of Uptime Kuma is attached to no server (unknown IP, host name
# not resolved…), kept as a key and its parameters so the monitors page can
# explain it in the language of the reader.
class AddUnmatchedReasonToUptimeKumaMonitors < ActiveRecord::Migration[8.1]
  def change
    add_column :uptime_kuma_monitors, :unmatched_reason, :jsonb, null: false, default: {}
  end
end
