# Docker on the whole fleet (docker inventories): the containers in trouble
# (looping, unhealthy, stopped for long), then the images by repository with
# the tags in use on each server, the new versions published by the
# registries and the vulnerabilities (vulnerable images first). Filters: ?q=
# (image), ?group=, ?updates=1, ?fixable=1 (images with fixable CVEs).
# ?sort=cves|age|size orders the images (most CVEs, oldest, biggest first);
# the unused images and the disk space they take, by server, come below.
# ?tab=containers: every container of the fleet, ?show= one kind of them
# (CONTAINER_FILTERS). ?tab=cves: the vulnerabilities of the images, by image
# then by package, with the commands that update a fixable image on each server.
class DockerController < ApplicationController
  PER_PAGE = 100
  IMAGES_PER_PAGE = 20
  TABS = %w[images containers cves].freeze
  SORTS = %w[cves age size].freeze
  CONTAINER_FILTERS = %w[trouble host_access public].freeze
  # The CVEs of an image, counted in SQL, with the servers and containers
  # that run it; its packages are loaded when it is unfolded (#image_cves).
  ImageVulnerabilities = Data.define(:image, :cve_count, :fixable_count, :severity, :max_score, :servers, :package_count, :uses) do
    def self.frame_id(image) = "image-cves-#{Digest::MD5.hexdigest(image).first(12)}"
    def frame_id = self.class.frame_id(image)
  end
  PACKAGES_PER_PAGE = 50
  # servers: those with a container of the version; hosts: those that have it.
  Version = Data.define(:tag, :image, :servers, :hosts, :state, :update, :cves, :fixable, :severity, :created_at, :size)
  # The unused images of a server, their size, and what `docker system df`
  # says can be reclaimed (images shared layers: less than their sum).
  UnusedImages = Data.define(:server, :count, :size, :reclaimable)
  Repository = Data.define(:name, :versions) do
    def servers = versions.flat_map(&:servers).uniq
    def created_at = versions.filter_map(&:created_at).min
    def size = versions.sum(&:size)
    def updates? = versions.any? { |version| version.state == :available }
    def cves = versions.sum(&:cves)
    def fixable? = versions.any? { |version| version.fixable.positive? }
    def unused? = versions.all? { |version| version.servers.empty? }
  end

  # The packages of an image and their CVEs (lazy frame of the CVE tab).
  def image_cves
    @group = ServerGroup.find_by(id: params[:group]) if params[:group].present?
    @image = params[:image].to_s
    rows = ServerVulnerability.images.where(image: @image)
    rows = rows.where(server_id: Server.in_group(@group).select(:id)) if @group
    @pager = paginate(PackageVulnerabilities.new(rows).groups, per_page: PACKAGES_PER_PAGE)
    @frame_id = ImageVulnerabilities.frame_id(@image)
    render layout: false
  end

  def index
    @groups = ServerGroup.order(:name)
    @group = @groups.find { |group| group.id.to_s == params[:group].to_s } if params[:group].present?
    @q = params[:q].to_s.strip.first(100)
    @updates_only = params[:updates] == "1"
    @fixable_only = params[:fixable] == "1"
    servers = (@group ? Server.in_group(@group) : Server.all).order(:name).includes(:inventory_snapshots).to_a
    dockers = servers.filter_map { |server| [ server, server.inventory("docker").data ] if server.inventory("docker")&.collected? && server.inventory("docker").data["docker"] == "ok" }
    @tab = params[:tab].presence_in(TABS) || "images"
    image_rows = ServerVulnerability.images.where(server: servers)
    @image_vulnerability_count = image_rows.distinct.count(:cve)
    @container_count = dockers.sum { |_, data| Array(data["containers"]).size }
    return index_cves(servers, dockers) if @tab == "cves"
    return index_containers(dockers) if @tab == "containers"

    @troubled = dockers.flat_map { |server, data| Array(data["containers"]).select { |container| container["looping"] || container["health"] == "unhealthy" || container["stopped_long"] }.map { |container| [ server, container ] } }
    @troubled.sort_by! { |server, container| [ container["stopped_long"] && !container["looping"] && container["health"] != "unhealthy" ? 1 : 0, server.name, container["name"] ] }
    @repositories = repositories(dockers)
    @repositories.select! { |repository| repository.name.downcase.include?(@q.downcase) } if @q.present?
    @repositories.select!(&:updates?) if @updates_only
    @repositories.select!(&:fixable?) if @fixable_only
    @sort = params[:sort].presence_in(SORTS)
    @unused_images = unused_images(dockers)

    @summary = { servers: dockers.size, containers: @container_count,
                 running: dockers.sum { |_, data| Array(data["containers"]).count { |container| container["state"] == "running" } },
                 updates: @repositories.count(&:updates?), troubled: @troubled.count { |_, container| container["looping"] || container["health"] == "unhealthy" },
                 image_cves: @image_vulnerability_count, vulnerable_images: image_rows.distinct.count(:image), image_fixable: image_rows.fixable.distinct.count(:cve) }
    @pager = paginate(@repositories.sort_by { |repository| sort_key(repository) }, per_page: PER_PAGE)
    @repositories = @pager.records
  end

  # Whether a container is of this kind (CONTAINER_FILTERS): to watch (looping,
  # unhealthy, stopped for long), root on the host (privileged or Docker
  # socket), or with a port published on every interface.
  def self.container_kind?(container, kind)
    case kind
    when "trouble" then container["looping"] || container["health"] == "unhealthy" || container["stopped_long"]
    when "host_access" then container["privileged"] || container["docker_socket"]
    when "public" then Array(container["ports"]).any? { |port| port["exposure"] == "all" }
    end.present?
  end

  private

  def sort_key(repository)
    case @sort
    when "cves" then [ -repository.cves, repository.name ]
    when "age" then [ repository.created_at || Time.current, repository.name ]
    when "size" then [ -repository.size, repository.name ]
    else [ repository.fixable? ? 0 : 1, repository.updates? ? 0 : 1, -repository.cves, repository.name ]
    end
  end

  # Every container of the fleet: in trouble first, then running, then by
  # server; ?show= keeps one kind, ?q= matches the name, image or project.
  def index_containers(dockers)
    containers = dockers.flat_map { |server, data| Array(data["containers"]).map { |container| [ server, container ] } }
    @summary = { servers: dockers.size, containers: containers.size, running: containers.count { |_, container| container["state"] == "running" },
                 **CONTAINER_FILTERS.to_h { |kind| [ kind.to_sym, containers.count { |_, container| self.class.container_kind?(container, kind) } ] } }
    @show = params[:show].presence_in(CONTAINER_FILTERS)
    containers.select! { |_, container| self.class.container_kind?(container, @show) } if @show
    if @q.present?
      query = @q.downcase
      containers.select! { |_, container| container.values_at("name", "image", "project", "service").compact.any? { |text| text.downcase.include?(query) } }
    end
    sorted = containers.sort_by do |server, container|
      [ container["looping"] || container["health"] == "unhealthy" ? 0 : container["state"] == "running" ? 1 : 2, server.name, container["name"] ]
    end
    @pager = paginate(sorted, per_page: PER_PAGE)
    @containers = @pager.records
    render :containers
  end

  # The servers with images no container uses, the most space to reclaim first.
  def unused_images(dockers)
    dockers.filter_map do |server, data|
      unused = Array(data["images"]).reject { |image| image["used"] }
      next if unused.empty?

      UnusedImages.new(server: server, count: unused.size, size: unused.sum { |image| image["size"].to_i }, reclaimable: data.dig("disk", "images", "reclaimable"))
    end.sort_by { |unused| [ -(unused.reclaimable || unused.size), unused.server.name ] }
  end

  def index_cves(servers, dockers)
    rows = ServerVulnerability.images.where(server: servers)
    rows = rows.where("server_vulnerabilities.image ILIKE ?", "%#{ServerVulnerability.sanitize_sql_like(@q)}%") if @q.present?
    containers = dockers.flat_map { |server, data| Array(data["containers"]).map { |container| [ server, container ] } }
    by_id = servers.index_by(&:id)
    images = rows.left_joins(:rating).group(:image).pluck(
      :image, Arel.sql("COUNT(DISTINCT server_vulnerabilities.cve)"),
      Arel.sql("COUNT(DISTINCT server_vulnerabilities.cve) FILTER (WHERE server_vulnerabilities.fixed_version IS NOT NULL)"),
      PackageVulnerabilities::WORST_SEVERITY, Arel.sql("MAX(cve_ratings.score)"),
      Arel.sql("ARRAY_AGG(DISTINCT server_vulnerabilities.server_id)"), Arel.sql("COUNT(DISTINCT server_vulnerabilities.source_package)")
    ).map do |image, cves, fixable, severity, score, server_ids, packages|
      touched = server_ids.filter_map { |id| by_id[id] }.sort_by(&:name)
      ImageVulnerabilities.new(image: image, cve_count: cves, fixable_count: fixable, severity: severity || "unknown", max_score: score, servers: touched, package_count: packages,
                               uses: containers.select { |server, container| container["image"] == image && server_ids.include?(server.id) })
    end
    @pager = paginate(images.sort_by { |image| [ image.fixable_count.zero? ? 1 : 0, Vulnerability::SEVERITIES.keys.index(image.severity), -image.cve_count, image.image ] },
                      per_page: IMAGES_PER_PAGE)
    @images = @pager.records
    fixers = Hash.new { |hash, server| hash[server] = Vulnerabilities::FixCommands.new(server, ServerVulnerability.none) }
    @update_commands = @images.select { |image| image.fixable_count.positive? }
                              .to_h { |image| [ image.image, image.servers.map { |server| [ server, fixers[server].image_update(image.image) ] } ] }
    @summary = { images: images.size, cves: rows.distinct.count(:cve), fixable: rows.fixable.distinct.count(:cve),
                 servers: images.flat_map(&:servers).uniq.size }
    render :cves
  end

  # Images by repository ("nginx"), then by tag, with the servers that run them.
  def repositories(dockers)
    images = dockers.flat_map { |server, data| Array(data["images"]).select { |image| Array(image["tags"]).any? }.map { |image| [ server, image ] } }
    updates = ImageUpdate.for_images(images.map(&:last))
    cves = ServerVulnerability.images.group(:server_id, :image).pluck(:server_id, :image, Arel.sql("COUNT(DISTINCT cve)"), Arel.sql("COUNT(DISTINCT cve) FILTER (WHERE fixed_version IS NOT NULL)"),
                                                                    PackageVulnerabilities::WORST_SEVERITY)
                              .to_h { |server_id, image, total, fixable, severity| [ [ server_id, image ], [ total, fixable, severity ] ] }
    images.group_by { |_, image| image["tags"].first.rpartition(":").first }.map do |name, uses|
      versions = uses.group_by { |_, image| image["tags"].first }.map do |tag, tag_uses|
        counts = tag_uses.map { |server, image| cves.fetch([ server.id, image["reference"] || tag ], [ 0, 0, nil ]) }
        severities = counts.filter_map(&:last)
        created = tag_uses.filter_map { |_, image| Time.zone.parse(image["created_at"]) if image["created_at"] }.min
        Version.new(tag: tag.rpartition(":").last, image: tag_uses.first.last, servers: tag_uses.select { |_, image| image["used"] }.map(&:first).uniq,
                    hosts: tag_uses.map(&:first).uniq, created_at: created, size: tag_uses.map { |_, image| image["size"].to_i }.max,
                    state: tag_uses.map { |_, image| ImageUpdate.state_for(image, updates) }.then { |states| states.include?(:available) ? :available : states.include?(:current) ? :current : :unknown },
                    update: updates[tag],
                    cves: counts.map(&:first).max.to_i, fixable: counts.map(&:second).max.to_i,
                    severity: severities.min_by { |severity| Vulnerability::SEVERITIES.keys.index(severity) })
      end
      Repository.new(name: name, versions: versions.sort_by(&:tag))
    end
  end
end
