require "test_helper"

class ImageRegistry::UpdateCheckTest < ActiveSupport::TestCase
  PULLED = "sha256:#{"1" * 64}"
  NEWER = "sha256:#{"2" * 64}"

  class FakeClient
    attr_reader :asked

    def initialize(digests, tags = {}) = (@digests = digests) && (@tags = tags) && (@asked = [])

    def tags(reference) = @tags.fetch(reference.repository, [])

    def digest(reference)
      @asked << "#{reference.registry}/#{reference.repository}:#{reference.tag}"
      value = @digests.fetch(reference.repository) { raise ImageRegistry::Error, "Tag introuvable sur le registre" }
      value.is_a?(Class) ? raise(value, "limite") : value
    end
  end

  def docker(server, images)
    server.inventory_snapshots.create!(category: "docker", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                       data: { "docker" => "ok", "containers" => [], "images" => images })
  end

  def image(tag, digest = PULLED, used: true) = { "id" => "sha256:#{tag.hash.abs}", "tags" => [ tag ], "digests" => [ "#{tag.split(":").first}@#{digest}" ], "used" => used }

  setup do
    docker(servers(:web), [ image("nginx:1.27"), image("ghcr.io/acme/app:2"), image("redis:7", used: false) ])
    docker(servers(:db), [ image("nginx:1.27", NEWER), { "id" => "sha256:x", "tags" => [], "digests" => [] } ])
  end

  test "asks each tag of the fleet once, remembers the digests and errors, compares with the pulled image" do
    client = FakeClient.new("library/nginx" => NEWER, "acme/app" => PULLED)
    assert_equal "3 images suivies, 2 vérifiée(s), 1 en échec", ImageRegistry::UpdateCheck.call(client: client)
    assert_equal [ "docker.io/library/nginx:1.27", "ghcr.io/acme/app:2", "docker.io/library/redis:7" ], client.asked

    updates = ImageUpdate.all.index_by(&:reference)
    assert_equal [ NEWER, nil ], updates["nginx:1.27"].values_at(:remote_digest, :error)
    assert_equal "Tag introuvable sur le registre", updates["redis:7"].error
    assert_equal :available, ImageUpdate.state_for(image("nginx:1.27"), updates)
    assert_equal :current, ImageUpdate.state_for(image("nginx:1.27", NEWER), updates)
    assert_equal :current, ImageUpdate.state_for(image("ghcr.io/acme/app:2"), updates)
    assert_equal :unknown, ImageUpdate.state_for(image("redis:7"), updates)

    again = FakeClient.new({})
    ImageRegistry::UpdateCheck.call(client: again)
    assert_empty again.asked, "checked less than 6 hours ago"
  end

  test "a rate-limited registry is left for the next run" do
    client = FakeClient.new("library/nginx" => ImageRegistry::Client::RateLimited, "acme/app" => PULLED)
    ImageRegistry::UpdateCheck.call(client: client)
    assert_equal [ "docker.io/library/nginx:1.27", "ghcr.io/acme/app:2" ], client.asked, "redis (Docker Hub too) not asked"
  end

  test "a new version is logged and becomes a Docker reason when the Docker alerts ask for it" do
    AppSetting.current.update!(docker_alert_updates: true)
    ImageRegistry::UpdateCheck.call(client: FakeClient.new("library/nginx" => PULLED, "acme/app" => PULLED))
    assert_equal 0, Activity.of_kind(:image_update_available).count
    ImageUpdate.update_all(checked_at: 1.day.ago)

    ImageRegistry::UpdateCheck.call(client: FakeClient.new("library/nginx" => NEWER, "acme/app" => PULLED))
    assert_equal [ "Nouvelle version de l'image nginx:1.27 pour « Web »" ], Activity.of_kind(:image_update_available).map(&:summary), "Database already has it"
    assert_includes servers(:web).reload.docker_reason_texts, "1 image Docker à mettre à jour"
  end

  test "registry credentials of the settings, one line each" do
    assert_equal({ "ghcr.io" => %w[alice ghp_x], "docker.io" => %w[bob dckr] }, ImageRegistry::UpdateCheck.credentials("ghcr.io alice ghp_x\n\nindex.docker.io bob dckr\nbroken\n"))
  end
  test "a pinned version also gets the last fix of its series (an update to make) and the last version of its major" do
    servers(:web).inventory_snapshots.destroy_all
    docker(servers(:web), [ image("redis:7.0.11") ])
    client = FakeClient.new({ "library/redis" => PULLED }, { "library/redis" => %w[7.0.11 7.0.15 7.4.6 8.0.1 latest] })
    AppSetting.current.update!(docker_alert_updates: true)
    ImageRegistry::UpdateCheck.call(client: client)

    update = ImageUpdate.find_by!(reference: "redis:7.0.11")
    assert_equal [ "7.0.15", "7.4.6" ], [ update.latest_patch, update.latest_in_major ]
    assert_equal :available, ImageUpdate.state_for(image("redis:7.0.11"), { "redis:7.0.11" => update }), "same digest, but a newer fix exists"
    assert_equal 0, Activity.where(kind: "image_update_available").count, "not on the first check"

    update.update!(checked_at: 1.day.ago)
    client = FakeClient.new({ "library/redis" => PULLED }, { "library/redis" => %w[7.0.11 7.0.16 7.4.6] })
    ImageRegistry::UpdateCheck.call(client: client)
    assert_equal "7.0.16", update.reload.latest_patch
    assert_equal 1, Activity.where(kind: "image_update_available").count, "a newer fix is logged"
  end
end
