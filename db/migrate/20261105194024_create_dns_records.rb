# One DNS of the fleet, fed by sources (phase 14): the DNS records of the
# OVHcloud extension (ovh_resources of kind dns_record) and of Technitium
# (technitium_records) move into dns_records; the manual attachments, by
# name and common to every source, into dns_links.
class CreateDnsRecords < ActiveRecord::Migration[8.1]
  def up
    create_table :dns_records do |t|
      t.string :source, null: false
      t.string :source_id, null: false
      t.string :zone, null: false
      t.string :name, null: false
      t.string :record_type, null: false
      t.string :value, null: false
      t.integer :ttl
      t.boolean :disabled, null: false, default: false
      t.references :server, foreign_key: { on_delete: :nullify }
      t.string :matched_by
      t.string :matched_address
      t.timestamps
    end
    add_index :dns_records, %i[source source_id], unique: true
    add_index :dns_records, :name

    create_table :dns_links do |t|
      t.string :name, null: false, index: { unique: true }
      t.references :server, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.timestamps
    end

    execute <<~SQL
      INSERT INTO dns_records (source, source_id, zone, name, record_type, value, ttl, server_id, matched_by, matched_address, created_at, updated_at)
      SELECT 'ovh', external_id, COALESCE(data->>'zone', ''), lower(name), data->>'type', lower(COALESCE(data->>'target', '')),
             NULLIF(data->>'ttl', '')::integer, server_id,
             CASE matched_by WHEN 'address' THEN 'address' WHEN 'cname' THEN 'cname' WHEN 'manual' THEN 'manual' END, matched_address, created_at, updated_at
      FROM ovh_resources WHERE kind = 'dns_record' AND data->>'type' IN ('A', 'AAAA', 'CNAME') AND COALESCE(data->>'target', '') <> '';

      INSERT INTO dns_records (source, source_id, zone, name, record_type, value, ttl, disabled, server_id, matched_by, matched_address, created_at, updated_at)
      SELECT 'technitium', zone || '|' || name || '|' || record_type || '|' || value, zone, name, record_type, value, ttl, disabled, server_id,
             matched_by, matched_address, created_at, updated_at
      FROM technitium_records;

      INSERT INTO dns_links (name, server_id, user_id, created_at, updated_at)
      SELECT DISTINCT ON (lower(r.name)) lower(r.name), l.server_id, l.user_id, l.created_at, l.updated_at
      FROM integration_links l JOIN integrations i ON i.id = l.integration_id
      JOIN ovh_resources r ON i.kind = 'ovh' AND l.external_id = 'dns_record:' || r.external_id AND r.kind = 'dns_record'
      ORDER BY lower(r.name), l.updated_at DESC;

      INSERT INTO dns_links (name, server_id, user_id, created_at, updated_at)
      SELECT DISTINCT ON (lower(l.external_id)) lower(l.external_id), l.server_id, l.user_id, l.created_at, l.updated_at
      FROM integration_links l JOIN integrations i ON i.id = l.integration_id AND i.kind = 'technitium'
      ORDER BY lower(l.external_id), l.updated_at DESC
      ON CONFLICT (name) DO NOTHING;

      DELETE FROM integration_links l USING integrations i
      WHERE i.id = l.integration_id AND (i.kind = 'technitium' OR (i.kind = 'ovh' AND l.external_id LIKE 'dns_record:%'));
      DELETE FROM ovh_resources WHERE kind = 'dns_record';

      -- The OVH records already reported outside the fleet keep their id (no new alert).
      UPDATE integrations SET state = jsonb_set(state, '{dns_outside}', COALESCE(
        (SELECT jsonb_agg(replace(entry, 'dns_record:', '')) FROM jsonb_array_elements_text(state->'dns_outside') AS entry), '[]'::jsonb))
      WHERE kind = 'ovh' AND jsonb_typeof(state->'dns_outside') = 'array';
    SQL
    drop_table :technitium_records
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
