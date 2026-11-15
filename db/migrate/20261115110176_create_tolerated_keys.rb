# Keys outside the keyring that the team knowingly accepts (a provider's
# support key, a colleague's key not worth a keyring entry), with the reason.
# A tolerated key is no longer reported as unknown.
class CreateToleratedKeys < ActiveRecord::Migration[8.1]
  def change
    create_table :tolerated_keys do |t|
      t.string :fingerprint, null: false, index: { unique: true }
      t.string :name
      t.text :reason, null: false
      t.references :user, foreign_key: { on_delete: :nullify }
      t.timestamps
    end
  end
end
