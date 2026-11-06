# Docker on the whole fleet (docker inventories): the containers in trouble
# (looping, unhealthy, stopped for long), then the images by repository with
# the tags in use on each server, the new versions published by the
# registries and the vulnerabilities. Filters: ?q= (image), ?group=, ?updates=1.
# ?tab=cves: the vulnerabilities of the images, by image then by package.
class DockerController < ApplicationController
  PER_PAGE = 100
  IMAGES_PER_PAGE = 20
  TABS = %w[images cves].freeze
  # The CVEs of an image, counted in SQL, with the servers and containers
  # that run it; its packages are loaded when it is unfolded (#image_cves).
  ImageVulnerabilities = Data.define(:image, :cve_count, :fixable_count, :severity, :max_score, :servers, :package_count, :uses) do
    def frame_id = "image-cves-#{Digest::MD5.hexdigest(image).first(12)}"
  end
  PACKAGES_PER_PAGE = 50
  Version = Data.define(:tag, :image, :servers, :state, :cves, :fixable)
  Repository = Data.define(:name, :versions) do
    def servers = versions.flat_map(&:servers).uniq
    def updates? = versions.any? { |version| version.state == :available }
    def cves = versions.sum(&:cves)
    def unused? = versions.all? { |version| version.servers.empty? }
  end

  # The packages of an image and their CVEs (lazy frame of the CVE tab).
  def image_cves
    @group = ServerGroup.find_by(id: params[:group]) if params[:group].present?
    @image = params[:image].to_s
    rows = ServerVulnerability.images.where(image: @image)
    rows = rows.where(server_id: Server.in_group(@group).select(:id)) if @group
    @pager = paginate(PackageVulnerabilities.new(rows).groups, per_page: PACKAGES_PER_PAGE)
    @frame_id = ImageVulnerabilities.new(image: @image, cve_count: 0, fixable_count: 0, severity: nil, max_score: nil, servers: [], package_count: 0, uses: []).frame_id
    render layout: false
  end

  def index
    @groups = ServerGroup.order(:name)
    @group = @groups.find { |group| group.id.to_s == params[:group].to_s } if params[:group].present?
    @q = params[:q].to_s.strip.first(100)
    @updates_only = params[:updates] == "1"
    servers = (@group ? Server.in_group(@group) : Server.all).order(:name).includes(:inventory_snapshots).to_a
    dockers = servers.filter_map { |server| [ server, server.inventory("docker").data ] if server.inventory("docker")&.collected? && server.inventory("docker").data["docker"] == "ok" }

    @troubled = dockers.flat_map { |server, data| Array(data["containers"]).select { |container| container["looping"] || container["health"] == "unhealthy" || container["stopped_long"] }.map { |container| [ server, container ] } }
    @troubled.sort_by! { |server, container| [ container["stopped_long"] && !container["looping"] && container["health"] != "unhealthy" ? 1 : 0, server.name, container["name"] ] }
    @repositories = repositories(dockers)
    @repositories.select! { |repository| repository.name.downcase.include?(@q.downcase) } if @q.present?
    @repositories.select!(&:updates?) if @updates_only
    @tab = params[:tab].presence_in(TABS) || "images"
    @image_vulnerability_count = ServerVulnerability.images.where(server: servers).distinct.count(:cve)
    return index_cves(servers, dockers) if @tab == "cves"

    @summary = { servers: dockers.size, containers: dockers.sum { |_, data| Array(data["containers"]).size },
                 running: dockers.sum { |_, data| Array(data["containers"]).count { |container| container["state"] == "running" } },
                 updates: @repositories.count(&:updates?), troubled: @troubled.count { |_, container| container["looping"] || container["health"] == "unhealthy" } }
    @pager = paginate(@repositories.sort_by { |repository| [ repository.updates? ? 0 : 1, -repository.cves, repository.name ] }, per_page: PER_PAGE)
    @repositories = @pager.records
  end

  private

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
    @summary = { images: images.size, cves: rows.distinct.count(:cve), fixable: rows.fixable.distinct.count(:cve),
                 servers: images.flat_map(&:servers).uniq.size }
    render :cves
  end

  # Images by repository ("nginx"), then by tag, with the servers that run them.
  def repositories(dockers)
    images = dockers.flat_map { |server, data| Array(data["images"]).select { |image| Array(image["tags"]).any? }.map { |image| [ server, image ] } }
    updates = ImageUpdate.for_images(images.map(&:last))
    cves = ServerVulnerability.images.group(:server_id, :image).pluck(:server_id, :image, Arel.sql("COUNT(DISTINCT cve)"), Arel.sql("COUNT(DISTINCT cve) FILTER (WHERE fixed_version IS NOT NULL)"))
                              .to_h { |server_id, image, total, fixable| [ [ server_id, image ], [ total, fixable ] ] }
    images.group_by { |_, image| image["tags"].first.rpartition(":").first }.map do |name, uses|
      versions = uses.group_by { |_, image| image["tags"].first }.map do |tag, tag_uses|
        counts = tag_uses.map { |server, image| cves.fetch([ server.id, image["reference"] || tag ], [ 0, 0 ]) }
        Version.new(tag: tag.rpartition(":").last, image: tag_uses.first.last, servers: tag_uses.select { |_, image| image["used"] }.map(&:first).uniq,
                    state: tag_uses.map { |_, image| ImageUpdate.state_for(image, updates) }.then { |states| states.include?(:available) ? :available : states.include?(:current) ? :current : :unknown },
                    cves: counts.map(&:first).max.to_i, fixable: counts.map(&:last).max.to_i)
      end
      Repository.new(name: name, versions: versions.sort_by(&:tag))
    end
  end
end
