# Ports a server is expected to expose publicly, on top of those of its
# groups (same format as server_groups.expected_ports): a single server can
# allow a port without opening it for the whole group.
class AddExpectedPortsToServers < ActiveRecord::Migration[8.1]
  def change
    add_column :servers, :expected_ports, :string
  end
end
