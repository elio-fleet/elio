# Addresses allowed to reach SSH (Elio, Coolify, an office…), used by the
# suggested firewall rules and the firewall prompt; each group of servers
# may choose some of them (none chosen = the whole list).
class CreateSshSources < ActiveRecord::Migration[8.1]
  def change
    create_table :ssh_sources do |t|
      t.string :name, null: false
      t.string :cidr, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :ssh_sources, "lower(name)", unique: true
    add_column :server_groups, :ssh_source_ids, :jsonb, null: false, default: []
  end
end
