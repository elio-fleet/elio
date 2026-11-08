# Stores what one Coolify connection read (Fetch::Result): replaces the
# connection's CoolifyResource rows, attaches each Coolify server to a server
# of the fleet and each resource to the server it runs on. Remembers the
# team, the version and the counts on the connection (its label and summary).
class Integrations::Coolify::Sync
  def initialize(connection, result)
    @connection = connection
    @result = result
  end

  def call
    before = CoolifyResource.where(integration_connection_id: @connection.id)
    previous = before.to_h { |resource| [ [ resource.kind, resource.uuid ], resource ] }
    touched = before.where.not(server_id: nil).pluck(:server_id)
    directory = ServerDirectory.new(Server.all)
    servers = @result.records.select { |record| record.kind == "server" }
    matches = servers.to_h { |record| [ record.uuid, match(directory, record) ] }

    CoolifyResource.transaction do
      kept = @result.records.map do |record|
        server, matched_by = matches[record.coolify_server_uuid]
        resource = CoolifyResource.find_or_initialize_by(integration_connection_id: @connection.id, kind: record.kind, uuid: record.uuid)
        resource.update!(name: record.name, status: record.status, coolify_server_uuid: record.coolify_server_uuid, data: record.data,
                         server: server, matched_by: matched_by)
        resource.id
      end
      CoolifyResource.where(integration_connection_id: @connection.id).where.not(id: kept).delete_all
    end

    log_failed_backups(previous)
    Server.where(id: touched + CoolifyResource.where(integration_connection_id: @connection.id).where.not(server_id: nil).pluck(:server_id)).find_each(&:refresh_health!)

    resources = @result.records.count { |record| record.kind != "server" }
    @connection.update!(state: @connection.state.merge("team" => @result.team["name"], "team_id" => @result.team["id"], "version" => @result.version,
                                                       "servers" => servers.size, "attached" => matches.values.count(&:present?), "resources" => resources).compact)
    I18n.t("integrations.coolify.summary", count: servers.size, attached: matches.values.count(&:present?), resources: resources)
  end

  private

  # A backup execution that failed since the last sync (never on the first
  # sync of a database: its old failures are history).
  def log_failed_backups(previous)
    CoolifyResource.where(integration_connection_id: @connection.id, kind: "database").find_each do |database|
      old = previous[[ "database", database.uuid ]] or next
      known = old.executions.map { |execution| execution["uuid"] }
      database.executions.select { |execution| execution["status"] == "failed" && known.exclude?(execution["uuid"]) }.first(1).each do
        Activity.record!(:coolify_backup_failed, server: database.server, user: nil, database: database.name, team: @connection.label)
      end
    end
  end

  # [server, how] or nil: by address (the IP Coolify connects to), by host
  # name or name in Elio, and the server hosting Coolify by the instance's
  # host name (Coolify calls it "localhost" / host.docker.internal).
  def match(directory, record)
    ip = record.data["ip"]
    found = directory.by_address(ip)
    return [ found.server, "address" ] if found

    [ [ ip, "host" ], [ record.name, "name" ] ].each do |host, how|
      server = directory.by_host(host, names: true)
      return [ server, how ] if server
    end
    return unless record.data["coolify_host"]

    server = directory.by_host(instance_host)
    [ server, "instance" ] if server
  end

  def instance_host = URI.parse(@connection.value(:url).to_s).host
end
