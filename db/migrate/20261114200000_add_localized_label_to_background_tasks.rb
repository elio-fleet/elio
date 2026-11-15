# The label of a run written in the language of each reader (LocalizedText),
# next to the plain label kept for the text search of the Journal.
class AddLocalizedLabelToBackgroundTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :background_tasks, :localized_label, :string
  end
end
