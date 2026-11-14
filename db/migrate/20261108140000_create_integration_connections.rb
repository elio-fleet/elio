# Several connections for one extension (several Coolify teams or
# instances…): each with its own fields, secrets and synchronization state.
class CreateIntegrationConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :integration_connections do |t|
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }
      t.string :name
      t.jsonb :settings, default: {}, null: false
      t.text :secrets
      t.jsonb :state, default: {}, null: false
      t.datetime :last_synced_at
      t.text :last_error
      t.timestamps
    end
  end
end
