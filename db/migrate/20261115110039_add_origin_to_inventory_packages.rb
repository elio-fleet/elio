# The repository each dpkg package was installed from ("Debian/bookworm-security",
# "Docker/bookworm", "local" for a package no repository provides), to spot
# backports and third-party packages. Null until the next packages inventory.
class AddOriginToInventoryPackages < ActiveRecord::Migration[8.1]
  def change
    add_column :inventory_packages, :origin, :string
  end
end
