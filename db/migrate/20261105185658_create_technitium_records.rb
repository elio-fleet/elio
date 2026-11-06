# DNS records read from a Technitium DNS Server (extension, phase 13.8):
# A, AAAA and CNAME, attached to the servers they point to.
class CreateTechnitiumRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :technitium_records do |t|
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
    add_index :technitium_records, %i[zone name record_type value], unique: true, name: "index_technitium_records_uniqueness"
  end
end
