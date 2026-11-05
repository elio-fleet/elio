# DNS alerts common to every DNS source (phase 14.3): the checkboxes of the
# OVHcloud and Technitium extensions become one DNS section; an alert is on
# if it was on in either. The records already reported outside the fleet
# are kept (no new alert), and the old "no DNS name" health reasons of each
# extension are dropped (the next health refresh writes the common one).
class AddDnsAlertsToAppSettings < ActiveRecord::Migration[8.1]
  def up
    add_column :app_settings, :dns_alert_outside, :boolean, null: false, default: false
    add_column :app_settings, :dns_alert_without_name, :boolean, null: false, default: false
    add_column :app_settings, :dns_without_name_ignored_group_ids, :jsonb, null: false, default: []
    add_column :app_settings, :dns_alert_conflict, :boolean, null: false, default: false
    add_column :app_settings, :dns_alert_state, :jsonb, null: false, default: {}

    execute <<~SQL
      UPDATE app_settings SET
        dns_alert_outside = EXISTS (SELECT 1 FROM integrations WHERE (kind = 'ovh' AND settings->>'alert_dns_outside' = 'true') OR (kind = 'technitium' AND settings->>'alert_outside' = 'true')),
        dns_alert_without_name = EXISTS (SELECT 1 FROM integrations WHERE kind IN ('ovh', 'technitium') AND settings->>'alert_server_without_dns' = 'true'),
        dns_alert_state = CASE WHEN NOT EXISTS (SELECT 1 FROM integrations WHERE (kind = 'ovh' AND jsonb_typeof(state->'dns_outside') = 'array')
                                                                          OR (kind = 'technitium' AND jsonb_typeof(state->'outside') = 'array'))
          THEN '{}'::jsonb -- never synchronized: the first sync logs nothing
          ELSE jsonb_build_object('outside', COALESCE((
          SELECT jsonb_agg(DISTINCT key) FROM (
            SELECT r.name || ' ' || r.value AS key FROM integrations i, jsonb_array_elements_text(i.state->'dns_outside') AS reported(ovh_id)
            JOIN dns_records r ON r.source = 'ovh' AND r.source_id = reported.ovh_id WHERE i.kind = 'ovh' AND jsonb_typeof(i.state->'dns_outside') = 'array'
            UNION
            SELECT entry FROM integrations i, jsonb_array_elements_text(i.state->'outside') AS entry WHERE i.kind = 'technitium' AND jsonb_typeof(i.state->'outside') = 'array'
          ) keys), '[]'::jsonb)) END;

      UPDATE integrations SET settings = settings - 'alert_dns_outside' - 'alert_server_without_dns', state = state - 'dns_outside' WHERE kind = 'ovh';
      UPDATE integrations SET settings = settings - 'alert_outside' - 'alert_server_without_dns', state = state - 'outside' WHERE kind = 'technitium';

      UPDATE servers SET health_reasons = COALESCE((SELECT jsonb_agg(reason) FROM jsonb_array_elements(health_reasons) AS reason
        WHERE reason->>'key' IS NULL OR reason->>'key' NOT IN ('integrations.ovh.health.no_dns', 'integrations.technitium.health.no_dns')), '[]'::jsonb)
      WHERE jsonb_typeof(health_reasons) = 'array';
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
