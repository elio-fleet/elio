require "shellwords"

# What to run on a server to fix some of its vulnerabilities (shown, copied
# by the user: Elio never runs them). One plan for the server's own packages,
# one per Docker image:
#
#   Vulnerabilities::FixCommands.new(server, server.server_vulnerabilities.where(cve: "CVE-…")).plans
#
# Plan#state: :available (the repositories offer the fix), :pending (a fixed
# version exists but the server had not seen it at its last inventory:
# refresh the package lists first), :image (pull the image again and
# recreate its containers), :none (no fix yet).
class Vulnerabilities::FixCommands
  Plan = Data.define(:image, :state, :commands, :packages, :reboot, :containers) do
    def host? = image.nil?
    def fixable? = state != :none
  end

  def initialize(server, rows)
    @server = server
    @rows = rows.to_a
  end

  def plans
    @plans ||= [ host_plan, *image_plans ].compact
  end

  private

  def host_plan
    rows = @rows.reject(&:image)
    return if rows.empty?

    groups = PackageVulnerabilities.new(rows, server: @server).groups.select { |group| group.target_version }
    return Plan.new(image: nil, state: :none, commands: [], packages: [], reboot: false, containers: []) if groups.empty?

    pending = groups.reject(&:available)
    # Every binary built from the source with an update, or (not seen yet)
    # the installed binaries affected.
    packages = groups.flat_map { |group| group.available ? group.upgrade_packages : group.binary_packages }.uniq.sort
    commands = []
    commands << root("apt-get update") if pending.any?
    commands << root("apt-get install --only-upgrade #{packages.shelljoin}") if packages.any?
    # The reboot is a note, not a command: pasting the whole block must not reboot the server.
    reboot = groups.any?(&:reboot?)
    Plan.new(image: nil, state: pending.any? ? :pending : :available, commands: commands, packages: packages, reboot: reboot, containers: [])
  end

  def image_plans
    @rows.select(&:image).group_by(&:image).sort_by(&:first).map do |image, rows|
      containers = containers_of(image)
      unless rows.any?(&:fixable?)
        next Plan.new(image: image, state: :none, commands: [], packages: [], reboot: false, containers: containers.map { |container| container["name"] })
      end

      Plan.new(image: image, state: :image, commands: image_commands(image, containers), packages: rows.map(&:source_package).uniq.sort, reboot: false,
               containers: containers.map { |container| container["name"] })
    end
  end

  # Compose projects: pull and recreate their services; other containers:
  # pull the image, then recreate them by hand (Elio does not know their options).
  def image_commands(image, containers)
    compose, alone = containers.partition { |container| container["working_dir"] && container["service"] }
    commands = compose.group_by { |container| container["working_dir"] }.sort.map do |directory, list|
      services = list.map { |container| container["service"] }.uniq.sort.shelljoin
      "cd #{directory.shellescape} && #{root("docker compose pull #{services}")} && #{root("docker compose up -d #{services}")}"
    end
    commands.unshift(root("docker pull #{image.shellescape}")) if alone.any? || compose.empty?
    commands
  end

  # The containers of the server that run this image (services inventory,
  # which knows the Compose labels; the Docker inventory otherwise).
  def containers_of(image)
    listed = Array(@server.inventory("services")&.data&.dig("containers"))
    listed = Array(@server.inventory("docker")&.data&.dig("containers")) if listed.empty?
    listed.select { |container| container["image"] == image }.sort_by { |container| container["name"].to_s }
  end

  def root(command)
    @server.username == "root" ? command : "sudo #{command}"
  end
end
