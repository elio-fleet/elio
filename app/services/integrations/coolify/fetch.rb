# Reads one Coolify connection (a team of an instance): the team, the
# version, the servers with their domains, and every resource (applications,
# services, standalone databases) with the server it runs on and its project
# / environment. Only what Elio shows is kept: never environment variables,
# Compose files, secrets (a `read` token gets them redacted anyway).
class Integrations::Coolify::Fetch
  Record = Data.define(:kind, :uuid, :name, :status, :coolify_server_uuid, :data)
  Result = Data.define(:team, :version, :records)

  def initialize(client)
    @client = client
  end

  def call
    team = @client.team
    environments = environments_by_id
    servers = @client.servers.map { |server| server_record(server) }
    resources = @client.resources.filter_map { |resource| resource_record(resource, environments) }
    Result.new(team: { "id" => team["id"], "name" => team["name"] }.compact, version: @client.version, records: servers + resources)
  end

  # "https://a.example.com,http://b.example.com:8080" → ["a.example.com", "b.example.com:8080"]
  def self.domains(fqdn) = fqdn.to_s.split(",").filter_map { |url| url.strip.sub(%r{\Ahttps?://}i, "").chomp("/").presence }.uniq

  private

  def server_record(server)
    settings = server["settings"] || {}
    domains = @client.server_domains(server["uuid"]).flat_map { |entry| Array(entry["domains"]) }.uniq.sort
    data = { "ip" => server["ip"], "user" => server["user"], "port" => server["port"], "description" => server["description"].presence,
             "reachable" => server["is_reachable"], "usable" => server["is_usable"], "coolify_host" => server["is_coolify_host"],
             "build_server" => settings["is_build_server"], "docker_version" => settings["docker_version"].presence,
             "proxy" => (server["proxy"].is_a?(Hash) ? server["proxy"]["type"] : nil), "domains" => domains }.compact
    Record.new(kind: "server", uuid: server["uuid"], name: server["name"].presence || server["uuid"], status: nil, coolify_server_uuid: server["uuid"], data: data)
  end

  def resource_record(resource, environments)
    kind = resource_kind(resource["type"])
    return unless kind && resource["uuid"].present?

    data = { "type" => resource["type"], "description" => resource["description"].presence, "restart_count" => resource["restart_count"],
             "last_online_at" => resource["last_online_at"] }.merge(environments[resource["environment_id"]] || {}).merge(send("#{kind}_data", resource)).compact
    server_uuid = resource.dig("destination", "server", "uuid") || resource.dig("server", "uuid")
    Record.new(kind: kind, uuid: resource["uuid"], name: resource["name"].presence || resource["uuid"], status: resource["status"].presence,
               coolify_server_uuid: server_uuid, data: data)
  end

  def resource_kind(type)
    case type.to_s
    when "application" then "application"
    when "service" then "service"
    when /\Astandalone-/ then "database"
    end
  end

  def application_data(app)
    image = [ app["docker_registry_image_name"], app["docker_registry_image_tag"] ].compact_blank.join(":").presence
    { "build_pack" => app["build_pack"], "domains" => self.class.domains(app["fqdn"]), "git_repository" => app["git_repository"].presence,
      "git_branch" => app["git_branch"].presence, "git_commit" => app["git_commit_sha"].presence, "image" => image,
      "health_check" => app["health_check_enabled"], "health_check_path" => app["health_check_path"].presence,
      "ports_exposes" => app["ports_exposes"].presence, "ports_mappings" => app["ports_mappings"].presence }
  end

  def service_data(service)
    applications = Array(service["applications"])
    { "service_type" => service["service_type"].presence, "domains" => applications.flat_map { |app| self.class.domains(app["fqdn"]) }.uniq,
      "images" => (applications + Array(service["databases"])).filter_map { |part| part["image"].presence }.uniq,
      "parts" => (applications + Array(service["databases"])).filter_map { |part| { "name" => part["name"], "status" => part["status"] }.compact if part["name"] } }
  end

  def database_data(database)
    { "engine" => database["type"].to_s.delete_prefix("standalone-"), "image" => database["image"].presence, "public" => database["is_public"],
      "public_port" => database["public_port"], "ports_mappings" => database["ports_mappings"].presence }
  end

  # environment id => { "project" => name, "environment" => name }
  def environments_by_id
    @client.projects.each_with_object({}) do |project, map|
      Array(@client.project(project["uuid"])["environments"]).each do |environment|
        map[environment["id"]] = { "project" => project["name"], "environment" => environment["name"] }
      end
    end
  end
end
