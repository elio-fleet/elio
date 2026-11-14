# Checks the registries for the tags of the Docker images of the fleet
# (docker inventories), at most once per ImageUpdate::FRESHNESS each and at
# most MAX per run; a registry that limits Elio is left until the next run.
# A pinned version tag ("redis:7.0.11") also gets the newer versions of its
# repository (ImageRegistry::Versions): the last fix of its series, the last
# version of its major. Logs image_update_available when a tag gets a new
# digest or a newer fix (if the Docker alerts ask for it), then refreshes the
# health of the Docker servers.
module ImageRegistry::UpdateCheck
  MAX = 300

  def self.call(client: ImageRegistry::Client.new(credentials: credentials))
    images = docker_images
    references = images.keys.filter_map { |text| ImageRegistry::Reference.parse(text)&.then { |reference| [ text, reference ] } }.to_h
    updates = ImageUpdate.where(reference: references.keys).index_by(&:reference)
    due = references.reject { |text, _| updates[text]&.checked_at&.after?(ImageUpdate::FRESHNESS.ago) }.first(MAX)
    limited = Set.new
    checked = failed = 0

    due.each do |text, reference|
      next if limited.include?(reference.registry)

      update = updates[text] || ImageUpdate.new(reference: text, registry: reference.registry, repository: reference.repository, tag: reference.tag)
      before = update.remote_digest
      patch_before = update.latest_patch
      begin
        newer = ImageRegistry::Versions.version_tag?(reference.tag) ? ImageRegistry::Versions.newer(reference.tag, client.tags(reference)) : {}
        update.update!(remote_digest: client.digest(reference), latest_patch: newer[:patch], latest_in_major: newer[:major], checked_at: Time.current, error: nil)
        checked += 1
        # Never on the first check of a tag: only what changed since the previous one.
        log_update(update, images[text]) if before && (before != update.remote_digest || (update.latest_patch && update.latest_patch != patch_before))
      rescue ImageRegistry::Client::RateLimited => e
        limited << reference.registry
        update.update!(checked_at: Time.current, error: e.message)
        failed += 1
      rescue ImageRegistry::Error => e
        update.update!(checked_at: Time.current, error: e.message)
        failed += 1
      end
    end
    servers_with_docker.each(&:refresh_health!)
    I18n.t("image_registry.update_check.summary", images: I18n.t("image_registry.update_check.images", count: references.size), checked: checked) + (failed.positive? ? I18n.t("image_registry.update_check.failed", count: failed) : "")
  end

  # { "nginx:1.27" => [[server, image], …] } from the docker inventories.
  def self.docker_images
    Inventory::Snapshot.where(category: "docker").where.not(collected_at: nil).includes(:server).each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |snapshot, images|
      Array(snapshot.data["images"]).each { |image| images[image["tags"].first] << [ snapshot.server, image ] if Array(image["tags"]).any? }
    end
  end

  def self.servers_with_docker = Server.where(id: Inventory::Snapshot.where(category: "docker").select(:server_id)).includes(:inventory_snapshots)

  # "ghcr.io alice ghp_…" lines of the settings → { "ghcr.io" => ["alice", "ghp_…"] }.
  def self.credentials(text = AppSetting.current.docker_registry_credentials)
    text.to_s.lines.filter_map do |line|
      registry, user, token = line.split
      [ registry == "index.docker.io" ? "docker.io" : registry, [ user, token ] ] if token
    end.to_h
  end

  def self.log_update(update, uses)
    return unless AppSetting.current.docker_alert_updates

    uses.select { |_, image| ImageUpdate.state_for(image, { update.reference => update }) == :available }.map(&:first).uniq.each do |server|
      Activity.record!(:image_update_available, server: server, user: nil, image: update.reference)
    end
  end
  private_class_method :docker_images, :servers_with_docker, :log_update
end
