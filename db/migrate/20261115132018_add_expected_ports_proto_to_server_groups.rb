# The protocol given to a group's expected ports written without one ("22, 80"
# then means TCP only). Empty, as before: such a port is expected in TCP and UDP.
class AddExpectedPortsProtoToServerGroups < ActiveRecord::Migration[8.1]
  def change
    add_column :server_groups, :expected_ports_proto, :string
  end
end
