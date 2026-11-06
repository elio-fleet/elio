class CreateServerNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :server_notes do |t|
      t.references :server, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.text :body, null: false
      t.timestamps
    end
    add_index :server_notes, %i[server_id created_at]
  end
end
