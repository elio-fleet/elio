# The state of Docker on a server (containers in trouble, vulnerable images,
# images to update) is computed apart from the health of the server itself:
# updating a server's packages no longer leaves it "to watch" because of its
# images. docker_alert_vulnerabilities: whether the CVEs of the images count
# in that state. The notification channels that received the health changes
# receive the Docker changes too (the container reasons used to be health
# reasons); the states are computed by Inventory::HealthStatus::VERSION.
class AddDockerStatusToServers < ActiveRecord::Migration[8.1]
  KINDS = { "health_warning" => "docker_warning", "health_critical" => "docker_critical", "health_recovered" => "docker_recovered" }.freeze

  def up
    add_column :servers, :docker_status, :string
    add_column :servers, :docker_reasons, :jsonb, null: false, default: []
    add_column :app_settings, :docker_alert_vulnerabilities, :boolean, null: false, default: true
    KINDS.each do |health, docker|
      execute <<~SQL.squish
        UPDATE notification_channels SET activity_kinds = activity_kinds || #{quote([ docker ].to_json)}::jsonb
        WHERE activity_kinds @> #{quote([ health ].to_json)}::jsonb AND NOT activity_kinds @> #{quote([ docker ].to_json)}::jsonb
      SQL
    end
  end

  def down
    KINDS.each_value do |docker|
      execute "UPDATE notification_channels SET activity_kinds = activity_kinds - #{quote(docker)}"
    end
    remove_column :app_settings, :docker_alert_vulnerabilities
    remove_column :servers, :docker_reasons
    remove_column :servers, :docker_status
  end

  private

  def quote(value) = connection.quote(value)
end
