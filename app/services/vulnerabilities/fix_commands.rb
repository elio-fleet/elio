require "shellwords"

# What to run on a server to fix some of its vulnerabilities (shown, copied
# by the user: Elio never runs them). One plan for the server's own packages,
# one per Docker image:
#
#   Vulnerabilities::FixCommands.new(server, server.server_vulnerabilities.where(cve: "CVE-…")).plans
#
# And, for the whole server, an ordered plan (most serious first):
#
#   fix = Vulnerabilities::FixCommands.new(server, server.server_vulnerabilities.fixable)
#   fix.system_plan # every package of the system to update, in one apt command
#   fix.steps       # by severity: the system packages, each Compose project, each image used without Compose
#
# Or how to update one image on the server: `fix.image_update("nginx:1.27")`.
#
# `rows`: ServerVulnerability records already loaded, or a relation (read
# aggregated in SQL by PackageVulnerabilities: a server can have thousands).
#
# Plan#state: :available (the repositories offer the fix), :pending (a fixed
# version exists but the server had not seen it at its last inventory:
# refresh the package lists first), :reboot (the fixed kernel is already
# installed: only a reboot is left), :image (pull the image again and
# recreate its containers), :none (no fix yet).
class Vulnerabilities::FixCommands
  Plan = Data.define(:image, :state, :commands, :packages, :reboot, :containers) do
    def host? = image.nil?
    def fixable? = state != :none
  end

  # One step of the ordered plan. kind: :packages (the system packages whose
  # most serious fixed CVE has this severity), :reboot (the fixed kernel is
  # installed, the server runs an older one: no command), :compose (one Compose project:
  # `name`, its directory in `directory`), :image (one image, `name`, pulled
  # again; its containers started without Compose are recreated by hand).
  Step = Data.define(:kind, :severity, :name, :directory, :commands, :packages, :images, :containers, :cves, :reboot)

  def initialize(server, rows)
    @server = server
    @rows = rows
  end

  def plans
    @plans ||= [ host_plan, *image_plans ].compact
  end

  # The plan of the system packages (nil when the rows hold none).
  def system_plan = plans.find(&:host?)

  # The commands that update an image on this server, whatever its rows:
  # each Compose project using it pulled and recreated, `docker pull` else.
  def image_update(image) = image_commands(image, containers_of(image))

  def steps
    @steps ||= (package_steps + compose_steps + image_steps).each_with_index
                                                            .sort_by { |step, index| [ Vulnerability::SEVERITIES.keys.index(step.severity) || 9, index ] }
                                                            .map(&:first)
  end

  private

  def groups
    @groups ||= PackageVulnerabilities.new(@rows, server: @server).groups
  end

  def host_groups = groups.reject(&:image)

  def host_plan
    return if host_groups.empty?

    fixable = host_groups.select(&:target_version)
    return Plan.new(image: nil, state: :none, commands: [], packages: [], reboot: false, containers: []) if fixable.empty?

    to_install = fixable.reject(&:awaiting_reboot?)
    pending = to_install.reject(&:available)
    packages = packages_of(to_install)
    commands = []
    commands << root("apt-get update") if pending.any?
    commands << root("apt-get install --only-upgrade #{packages.shelljoin}") if packages.any?
    state = :reboot if to_install.empty?
    state ||= pending.any? ? :pending : :available
    # The reboot is a note, not a command: pasting the whole block must not reboot the server.
    Plan.new(image: nil, state: state, commands: commands, packages: packages, reboot: fixable.any?(&:reboot?), containers: [])
  end

  # Every binary built from the source with an update, or (not seen yet)
  # the installed binaries affected.
  def packages_of(groups)
    groups.flat_map { |group| group.available ? group.upgrade_packages : group.binary_packages }.uniq.sort
  end

  def image_plans
    groups.select(&:image).group_by(&:image).sort_by(&:first).map do |image, list|
      containers = containers_of(image).map { |container| container["name"] }
      next Plan.new(image: image, state: :none, commands: [], packages: [], reboot: false, containers: containers) if list.none?(&:target_version)

      Plan.new(image: image, state: :image, commands: image_commands(image, containers_of(image)), packages: list.map(&:source_package).uniq.sort,
               reboot: false, containers: containers)
    end
  end

  # Compose projects: pull and recreate their services; other containers:
  # pull the image, then recreate them by hand (Elio does not know their options).
  def image_commands(image, containers)
    compose, alone = containers.partition { |container| compose?(container) }
    commands = compose.group_by { |container| container["working_dir"] }.sort.map { |directory, list| compose_command(directory, list) }
    commands.unshift(root("docker pull #{image.shellescape}")) if alone.any? || compose.empty?
    commands
  end

  def compose_command(directory, containers)
    services = containers.map { |container| container["service"] }.uniq.sort.shelljoin
    "cd #{directory.shellescape} && #{root("docker compose pull #{services}")} && #{root("docker compose up -d #{services}")}"
  end

  def compose?(container) = container["working_dir"].present? && container["service"].present?

  # The system packages, one step per severity (that of the most serious
  # CVE each update fixes); refreshing the package lists comes first.
  def package_steps
    waiting, fixable = host_groups.select(&:target_version).partition(&:awaiting_reboot?)
    refresh = fixable.any? { |group| !group.available }
    seen = []
    reboot_steps(waiting) + fixable.group_by(&:fixable_severity).sort_by { |severity, _| Vulnerability::SEVERITIES.keys.index(severity) || 9 }.filter_map do |severity, list|
      packages = packages_of(list) - seen
      next if packages.empty?

      seen.concat(packages)
      commands = [ root("apt-get install --only-upgrade #{packages.shelljoin}") ]
      commands.unshift(root("apt-get update")) if refresh && seen.size == packages.size
      Step.new(kind: :packages, severity: severity, name: nil, directory: nil, commands: commands, packages: packages, images: [], containers: [],
               cves: list.flat_map(&:fixable).uniq.sort, reboot: list.any?(&:reboot?))
    end
  end

  # The kernel already updated, waiting for a reboot: a step without a
  # command (Elio does not hand out a reboot to paste).
  def reboot_steps(groups)
    groups.map do |group|
      Step.new(kind: :reboot, severity: group.fixable_severity, name: group.installed_kernel, directory: nil, commands: [], packages: [ group.source_package ],
               images: [], containers: [], cves: group.fixable, reboot: true)
    end
  end

  # The fixable images, with their containers: { image => [groups, containers] }.
  def fixable_images
    @fixable_images ||= groups.select { |group| group.image && group.target_version }.group_by(&:image).sort_by(&:first)
                              .to_h { |image, list| [ image, [ list, containers_of(image) ] ] }
  end

  # One step per Compose project running a fixable image: pull and recreate
  # only its services that use one.
  def compose_steps
    fixable_images.flat_map { |image, (list, containers)| containers.select { |container| compose?(container) }.map { |container| [ image, list, container ] } }
                  .group_by { |_, _, container| container["working_dir"] }.sort_by(&:first).map do |directory, entries|
      containers = entries.map(&:last)
      images = entries.map(&:first).uniq.sort
      list = entries.flat_map { |_, groups, _| groups }.uniq
      Step.new(kind: :compose, severity: worst(list), name: containers.filter_map { |container| container["project"].presence }.first || File.basename(directory),
               directory: directory, commands: [ compose_command(directory, containers) ], packages: list.map(&:source_package).uniq.sort, images: images,
               containers: containers.map { |container| container["name"] }.sort, cves: list.flat_map(&:fixable).uniq.sort, reboot: false)
    end
  end

  # One step per fixable image used outside Compose (or by no container).
  def image_steps
    fixable_images.filter_map do |image, (list, containers)|
      alone = containers.reject { |container| compose?(container) }
      next if containers.any? && alone.empty?

      Step.new(kind: :image, severity: worst(list), name: image, directory: nil, commands: [ root("docker pull #{image.shellescape}") ],
               packages: list.map(&:source_package).uniq.sort, images: [ image ], containers: alone.map { |container| container["name"] },
               cves: list.flat_map(&:fixable).uniq.sort, reboot: false)
    end
  end

  def worst(groups)
    groups.map(&:fixable_severity).min_by { |severity| Vulnerability::SEVERITIES.keys.index(severity) || 9 }
  end

  # The containers of the server that run this image (services inventory,
  # which knows the Compose labels; the Docker inventory otherwise).
  def containers_of(image)
    @containers ||= Array(@server.inventory("services")&.data&.dig("containers")).presence || Array(@server.inventory("docker")&.data&.dig("containers"))
    @containers.select { |container| container["image"] == image }.sort_by { |container| container["name"].to_s }
  end

  def root(command)
    @server.username == "root" ? command : "sudo #{command}"
  end
end
