# Containers that must run on a server (names, comma-separated): one that is
# missing or stopped makes its Docker state critical (Inventory::DockerStatus).
# The index serves the Docker filter of the server list.
class AddExpectedContainersToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :expected_containers, :string
    add_index :servers, :docker_status
  end
end
