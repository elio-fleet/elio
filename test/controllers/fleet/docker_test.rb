require "test_helper"

class DockerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  NOW = Time.zone.parse("2025-11-01 12:25")
  PULLED = "sha256:#{"1" * 64}"

  def docker(server)
    data = Inventory::Collectors::Docker.parse(Inventory::Collectors::Docker.sections(file_fixture("inventory/docker/debian13.txt").read), now: NOW)
    data["images"].each { |image| image["reference"] = image["tags"].first || image["id"] }
    data["scans"] = { "sha256:#{"a" * 64}" => { "method" => "elio", "at" => NOW.iso8601, "count" => 2 },
                      "sha256:#{"c" * 64}" => { "method" => "elio", "at" => NOW.iso8601, "error" => "Base Debian Security Tracker pas encore téléchargée" } }
    server.inventory_snapshots.create!(category: "docker", status: "ok", collected_at: NOW, checked_at: NOW, data: data.merge("docker" => "ok", "version" => "27.3.1"))
  end

  def cve(server, image, cve, fixed)
    server.server_vulnerabilities.create!(origin: "image", source: "debian", image: image, cve: cve, source_package: "openssl", packages: [ "libssl3" ],
                                          installed_version: "3.0.14-1~deb12u1", fixed_version: fixed, severity: "low")
  end

  setup do
    docker(servers(:web))
    cve(servers(:web), "nginx:1.27", "CVE-2024-9143", "3.0.15-1~deb12u1")
    cve(servers(:web), "nginx:1.27", "CVE-2024-6119", nil)
    ImageUpdate.create!(reference: "nginx:1.27", registry: "docker.io", repository: "library/nginx", tag: "1.27", remote_digest: "sha256:#{"9" * 64}", checked_at: NOW)
    ImageUpdate.create!(reference: "postgres:16", registry: "docker.io", repository: "library/postgres", tag: "16", remote_digest: "sha256:#{"3" * 64}", checked_at: NOW)
  end

  test "the server tab lists the containers (problems first) and the images with their update and vulnerabilities" do
    sign_in users(:viewer)
    travel_to(NOW) { get server_path(servers(:web), tab: "docker") }

    assert_select "nav.server-tabs a[data-tab=docker][aria-current=page]", text: /Docker\s*4/
    assert_select "#server-docker" do
      assert_select ".docker-summary", text: %r{2/4 conteneurs en cours\s+· 2 en difficulté\s+· 6 images \(2 inutilisées\)\s+· 1,14 Go d'images, 217 Mo récupérables\s+· analyse : Elio}
      assert_select "tr.docker-container-row:first-child[data-name=db] .container-state", text: "mauvaise santé"
      assert_select "tr.docker-container-row[data-name=worker] .container-state", text: "redémarre en boucle"
      assert_select "tr.docker-container-row[data-name=backup-once]", text: /arrêté\s+backup-once.*arrêté il y a 31 jours/m
      assert_select "tr.docker-container-row[data-name=web]", text: /12,5 Mo/
      assert_select "nav.docker-sections a[data-section=containers][aria-current=page]", text: /Conteneurs\s*4/
      assert_select "nav.docker-sections a[data-section=vulnerabilities]", text: /Vulnérabilités\s*2/
      assert_select "tr.docker-image", 0, "the images are in their section"
    end

    travel_to(NOW) { get server_path(servers(:web), tab: "docker", section: "images") }
    assert_select "#server-docker" do
      assert_select "tr.docker-container-row", 0
      assert_select "tr.docker-image[data-reference='nginx:1.27']", text: /nouvelle version.*2\s+dont 1 corrigeable/m
      assert_select "tr.docker-image[data-reference='nginx:1.27'] a[href=?]", server_path(servers(:web), tab: "docker", section: "vulnerabilities")
      assert_select "tr.docker-image[data-reference='postgres:16'] .image-update", text: "à jour"
      assert_select "tr.docker-image[data-reference='postgres:16']", text: /pas encore téléchargée/
      assert_select "tr.docker-image[data-reference='redis:latest']", text: /latest.*non/m
    end
  end

  test "the vulnerabilities section lists the CVEs of the images by package, explains how they are fixed" do
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "docker", section: "vulnerabilities")
    assert_select "#server-docker" do
      assert_select "nav.docker-sections a[data-section=vulnerabilities][aria-current=page] span.bg-warn-soft", "2"
      assert_select "li.vulnerability-package[data-package='openssl@nginx:1.27'][data-state=image]"
      assert_select "li.package-cve", 2
      assert_select "p", /Corrigées en mettant à jour l'image/
    end

    servers(:web).server_vulnerabilities.delete_all
    get server_path(servers(:web), tab: "docker", section: "vulnerabilities")
    assert_select ".image-vulnerabilities-empty", /Aucune vulnérabilité connue/
  end

  test "an unreadable Docker is explained, no tab without Docker" do
    servers(:web).inventory("docker").update!(status: "partial", message: "Docker illisible : permission denied", data: { "docker" => "unreadable", "containers" => [], "images" => [] })
    sign_in users(:viewer)
    get server_path(servers(:web), tab: "docker")
    assert_select ".docker-unreadable", /permission denied/

    get server_path(servers(:db))
    assert_select "nav.server-tabs a[data-tab=docker]", 0
  end

  test "the fleet page: containers in trouble, images by repository with their tags, updates and vulnerabilities" do
    sign_in users(:viewer)
    travel_to(NOW) do
      get docker_path

      assert_response :success
      assert_select "nav.main-nav a[aria-current=page][href=?]", docker_path
      assert_select "#stat-troubled .stat-value", "2"
      assert_select "#stat-updates .stat-value", "1"
      assert_select "#troubled-containers li.troubled-container", 3
      assert_select "#troubled-containers li.troubled-container", text: /redémarre en boucle\s+Web\s+worker.*12 redémarrages/m
      assert_select "tr.docker-repository-version:first-child[data-repository=nginx]", text: /nginx\s+1.27\s+Web\s+nouvelle version\s+Faible\s+2\s+dont 1 corrigeable/
      assert_select "tr.docker-repository-version[data-repository=nginx] .docker-version-cves .severity[data-severity=low]"
      assert_select "tr.docker-repository-version[data-repository=redis]", text: /aucun conteneur/
      assert_select "#stat-image-cves .stat-value", "2"
      assert_select "#stat-image-cves", /1 image Docker · 1 corrigeable/

      get docker_path(fixable: "1")
      assert_select "tr.docker-repository-version", 1
      assert_select "input[type=checkbox][name=fixable][checked]"

      get docker_path(updates: "1")
      assert_select "tr.docker-repository-version", 1
      get docker_path(q: "postgres")
      assert_select "tr.docker-repository-version[data-repository=postgres]", 1
    end
  end

  test "the Docker alerts of the settings make the Docker state, never the health of the server" do
    servers(:web).server_vulnerabilities.where(cve: "CVE-2024-9143").update_all(severity: "high")
    servers(:web).refresh_health!
    assert_equal "crit", servers(:web).docker_status
    assert_equal [ "Conteneur worker redémarre en boucle", "Conteneur db en mauvaise santé", "1 vulnérabilité grave corrigeable dans les images Docker" ],
                 servers(:web).docker_reason_texts
    assert_empty servers(:web).health_reason_texts.grep(/Conteneur|image/), "Docker is no longer a health reason"

    AppSetting.current.update!(docker_alert_unhealthy: false, docker_alert_restarts: false, docker_alert_updates: true)
    servers(:web).refresh_health!
    assert_equal "warn", servers(:web).docker_status, "images only: never critical"
    assert_equal [ "1 vulnérabilité grave corrigeable dans les images Docker", "1 image Docker à mettre à jour" ], servers(:web).docker_reason_texts

    AppSetting.current.update!(docker_alert_vulnerabilities: false, docker_alert_updates: false)
    servers(:web).refresh_health!
    assert_equal [ "ok", [] ], [ servers(:web).docker_status, servers(:web).docker_reasons ]
  end

  test "settings: alerts, registry credentials kept encrypted and never shown back, check now" do
    sign_in users(:one)
    get settings_docker_path
    assert_select "nav.settings-nav a[aria-current=page]", "Docker"
    assert_select "input[type=checkbox][name='app_setting[docker_alert_unhealthy]'][checked]"
    assert_select ".registries-configured", "Aucun identifiant enregistré."
    assert_select "tr.image-check", 2

    assert_select "input[type=checkbox][name='app_setting[docker_alert_vulnerabilities]'][checked]"

    patch settings_docker_path, params: { app_setting: { docker_alert_updates: "1", docker_alert_vulnerabilities: "0", docker_registry_credentials: "ghcr.io elio ghp_secret" } }
    assert_redirected_to settings_docker_path
    setting = AppSetting.current.reload
    assert setting.docker_alert_updates
    assert_not setting.docker_alert_vulnerabilities
    assert_equal "ghcr.io elio ghp_secret", setting.docker_registry_credentials
    assert_not_includes AppSetting.connection.select_value("SELECT docker_registry_credentials FROM app_settings"), "ghp_secret"

    get settings_docker_path
    assert_select ".registries-configured", /Identifiants enregistrés pour : ghcr.io/
    assert_no_match "ghp_secret", response.body

    patch settings_docker_path, params: { app_setting: { docker_alert_updates: "1", docker_registry_credentials: "" } }
    assert_equal "ghcr.io elio ghp_secret", AppSetting.current.reload.docker_registry_credentials, "left blank: kept"
    patch settings_docker_path, params: { app_setting: { docker_registry_credentials: "pas assez" } }
    assert_match "Identifiants refusés : ligne 1", flash[:alert]
    patch settings_docker_path, params: { app_setting: { docker_registry_credentials: "" }, clear_credentials: "1" }
    assert_nil AppSetting.current.reload.docker_registry_credentials

    post check_settings_docker_path
    task = BackgroundTask.sole
    assert_redirected_to task_path(task)
    assert_enqueued_with(job: RunAutomationJob, args: [ Automation.find_by!(kind: "docker_image_updates"), task ])
  end

  test "the server page shows the Docker state apart from the health: pill, Docker row, coloured tab" do
    servers(:web).refresh_health!
    sign_in users(:viewer)
    get server_path(servers(:web))
    assert_select "h1 ~ a.docker-pill[data-docker-status=crit][href=?]", server_path(servers(:web), tab: "docker"), text: "2"
    assert_select "#server-docker-state[data-docker-status=crit]" do
      assert_select ".badge", "Critique"
      assert_select "span", /Conteneur worker redémarre en boucle · Conteneur db en mauvaise santé/
    end
    assert_select ".tabs-bar a[data-tab=docker] span[data-tone=crit]", "2"
    assert_select "#server-health-details", text: /Conteneur/, count: 0
  end

  test "Docker fine: a grey whale with a check; no pill nor Docker row without Docker" do
    AppSetting.current.update!(docker_alert_unhealthy: false, docker_alert_restarts: false)
    servers(:web).refresh_health!
    sign_in users(:viewer)
    get server_path(servers(:web))
    assert_select "a.docker-pill[data-docker-status=ok][title='Docker : rien à signaler']"
    assert_select "#server-docker-state", text: /Rien à signaler/
    assert_select ".tabs-bar a[data-tab=docker] span[data-tone=crit]", 0

    get server_path(servers(:db))
    assert_select "a.docker-pill", 0
    assert_select "#server-docker-state", 0
  end

  test "the fleet list shows the pill and filters on the Docker state" do
    servers(:web).refresh_health!
    sign_in users(:viewer)
    get servers_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:web))} a.docker-pill[data-docker-status=crit]"
    assert_select "##{ActionView::RecordIdentifier.dom_id(servers(:db))} a.docker-pill", 0

    get servers_path(state: "docker_crit")
    assert_select "#servers tbody tr", 1
    get servers_path(state: "docker_warn")
    assert_select "#servers tbody tr", 0
    get servers_path(state: "docker_crit", view: "grid")
    assert_select "a.docker-pill[data-docker-status=crit]", 1
  end
end
