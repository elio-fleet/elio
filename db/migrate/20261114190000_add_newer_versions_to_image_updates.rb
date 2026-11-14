# Newer versions of a pinned tag found in the tags of its repository
# (ImageRegistry::Versions): the last fix of its series and the last version
# of its major, next to the digest check of the tag itself.
class AddNewerVersionsToImageUpdates < ActiveRecord::Migration[8.1]
  def change
    add_column :image_updates, :latest_patch, :string
    add_column :image_updates, :latest_in_major, :string
  end
end
