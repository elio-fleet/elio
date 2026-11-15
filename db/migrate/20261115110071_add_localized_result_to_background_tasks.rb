# The result of a run written in the language of each reader (LocalizedText),
# next to the plain result kept for the text search of the Journal: a French
# reader of an English installation saw "8/8 servers inventoried". The runs
# can now be filtered by kind, most recent first: an index for that list.
class AddLocalizedResultToBackgroundTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :background_tasks, :localized_result, :text
    add_index :background_tasks, %i[kind created_at]
  end
end
