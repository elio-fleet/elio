# An unknown key on a root account is now its own critical activity kind
# (unknown_root_key_detected) instead of a plain unknown_key_detected: the
# channels that received unknown keys keep receiving them on root.
class SubscribeChannelsToUnknownRootKeys < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      UPDATE notification_channels
      SET activity_kinds = activity_kinds || '["unknown_root_key_detected"]'::jsonb
      WHERE activity_kinds @> '["unknown_key_detected"]'::jsonb
        AND NOT activity_kinds @> '["unknown_root_key_detected"]'::jsonb
    SQL
  end

  def down
    execute <<~SQL
      UPDATE notification_channels
      SET activity_kinds = activity_kinds - 'unknown_root_key_detected'
    SQL
  end
end
