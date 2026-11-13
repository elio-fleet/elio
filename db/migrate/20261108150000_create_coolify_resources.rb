# What the Coolify extension reads, per connection (a team of an instance):
# its servers and the resources running on them (applications, services,
# databases), attached to the servers of the fleet. A connection deleted
# takes its resources with it.
class CreateCoolifyResources < ActiveRecord::Migration[8.1]
  def change
    create_table :coolify_resources do |t|
      t.references :integration_connection, null: false, foreign_key: { on_delete: :cascade }
      t.string :kind, null: false
      t.string :uuid, null: false
      t.string :name, null: false
      t.string :status
      t.string :coolify_server_uuid
      t.references :server, foreign_key: { on_delete: :nullify }
      t.string :matched_by
      t.jsonb :data, default: {}, null: false
      t.timestamps
    end
    add_index :coolify_resources, %i[integration_connection_id kind uuid], unique: true, name: "index_coolify_resources_unique"
  end
end
