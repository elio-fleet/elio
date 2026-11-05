require "test_helper"

# The interface read in English has no French text left: every text of the
# pages listed here comes from the translations. Data (server names,
# messages from the servers) is excluded by the fixtures, which are written
# without French words.
class EnglishInterfaceTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  # Accented letters of French, French punctuation, and common French words.
  FRENCH = /[àâçéèêëîïôûùüÿœ«»]|\b(?:le|la|les|des|du|une|est|sont|aucun|aucune|pour|avec|sans|dans|sur|serveurs?|clés?|tâches?|paramètres|groupes?|mise|jour|activité|vue|ensemble|voir|tout|rien|nouveaux?|nouvelles?|ajouter|supprimer|modifier|enregistrer|lancer|retour|fermer|oui|non|parc|inventaire|sondes?|disponible|corrige|empreinte|statut|nom|commande|fichier|ligne|taille|noyau|horloge|quand|couleur|registre|alertes|adresses?|cible|offre|projet|trousseau|conteneurs?|processus|correctif)\b/i

  # Texts and attributes a user reads, but those of `except` (data).
  def self.french_texts(html, scope: nil, except: [])
    document = Nokogiri::HTML(html)
    roots = scope ? document.css(scope) : [ document.at("body") || document ]
    roots.flat_map do |root|
      except.each { |selector| root.css(selector).each(&:remove) }
      root.css("script, style, template").each(&:remove)
      root.css("[lang]:not([lang^=en])").each(&:remove) # written in another language on purpose
      texts = root.xpath(".//text()").map(&:text)
      texts += root.css("[title], [aria-label], [placeholder], [alt]").flat_map { |node| %w[title aria-label placeholder alt].filter_map { node[_1] } }
      texts.map(&:squish).reject(&:empty?).select { |text| text.match?(FRENCH) }
    end.uniq
  end

  # Parts of every page.
  LAYOUT = [ ".sidebar", "#command-palette", "#confirm-dialog", "nav.pagination" ].freeze

  setup do
    app_settings(:main).update!(default_locale: "en")
    sign_in users(:one)
  end

  def assert_english(path, scope: nil, except: [])
    get path
    assert_response :success
    leftovers = self.class.french_texts(response.body, scope: scope, except: except)
    assert_empty leftovers, "French text on #{path}#{" (#{scope})" if scope}"
  end

  test "the layout of the signed-in pages" do
    assert_english root_path, scope: LAYOUT.join(", "), except: [ ".sidebar-groups", ".account-link" ]
  end

  test "the account pages" do
    assert_english account_path, except: [ ".sidebar-groups", ".account-link" ]
    assert_english new_two_factor_path, except: [ ".sidebar-groups", ".account-link", ".two-factor-secret" ]
    Invitation.create!(email: "dave@example.com", role: "viewer", invited_by: users(:one))
    assert_english settings_users_path, except: [ ".sidebar-groups", ".account-link" ]
  end

  test "the public pages" do
    sign_out :user
    get new_user_session_path, headers: { "Accept-Language" => "en" }
    assert_empty self.class.french_texts(response.body)
    get new_user_password_path, headers: { "Accept-Language" => "en" }
    assert_empty self.class.french_texts(response.body)
    invitation = Invitation.create!(email: "dave@example.com", role: "viewer", invited_by: users(:one))
    get invitation_acceptance_path(invitation.token), headers: { "Accept-Language" => "en" }
    assert_empty self.class.french_texts(response.body)
    get invitation_acceptance_path("nope"), headers: { "Accept-Language" => "en" }
    assert_empty self.class.french_texts(response.body)
  end

  test "the fleet pages" do
    data = [ ".sidebar-groups", ".account-link", "#servers td:nth-child(2)", ".server-card-header", ".server-group-filter", "#activities", "#recent-activity ul", "#attention ul" ]
    assert_english root_path, except: data
    assert_english servers_path, except: data
    assert_english servers_path(view: "grid"), except: data
    assert_english new_server_path, except: data
    assert_english edit_server_path(servers(:web)), except: data
    assert_english server_groups_path, except: data + [ "table td:first-child" ]
    assert_english new_server_group_path, except: data
    assert_english new_server_import_path, except: data
  end

  test "the inventory pages" do
    data = [ ".sidebar-groups", ".account-link", ".server-group-filter", "#servers td:nth-child(2)" ]
    %w[overview packages services ports schedules].each do |tab|
      assert_english server_path(servers(:web), tab: tab), except: data
    end
    assert_english server_packages_path(servers(:web)), except: data
    assert_english packages_path, except: data
    assert_english packages_path(q: "openssl"), except: data
    assert_english ports_path, except: data
    assert_english scheduled_tasks_path, except: data
  end

  test "the access pages" do
    data = [ ".sidebar-groups", ".account-link", "#public-keys td:first-child", ".key-comment", "pre", "code", "textarea" ]
    assert_english public_keys_path, except: data
    assert_english public_key_path(public_keys(:alice)), except: data
    assert_english new_public_key_path, except: data
    assert_english edit_public_key_path(public_keys(:alice)), except: data
    assert_english server_path(servers(:web), tab: "keys"), except: data
    servers(:web).notes.create!(body: "Front **nginx**", user: users(:one))
    assert_english server_path(servers(:web), tab: "notes"), except: data + [ ".note-body" ]
    assert_english settings_path, except: data
  end

  test "the activity, tasks and notifications pages" do
    data = [ ".sidebar-groups", ".account-link", "#activities li span.font-medium" ]
    Activity.record!(:server_unreachable, server: servers(:web))
    assert_english activities_path, except: data
    assert_english tasks_path, except: data
    assert_english settings_automations_path, except: data
    assert_english settings_notifications_path, except: data
    assert_english new_settings_notification_channel_path, except: data
  end

  test "an activity is summarized in the reader's language" do
    activity = Activity.record!(:health_warning, server: servers(:web), user: nil, reasons: [ Inventory::HealthStatus.reason("warn", :reboot_required).to_h ])
    assert_equal "“Web” is to watch: Reboot required", I18n.with_locale(:en) { activity.summary }
    assert_equal "« Web » est à surveiller : Redémarrage requis", I18n.with_locale(:fr) { activity.summary }
  end

  test "the security pages" do
    data = [ ".sidebar-groups", ".account-link", "pre", "code", ".font-mono" ]
    assert_english vulnerabilities_path, except: data
    assert_english vulnerabilities_path(view: "cves"), except: data
    assert_english server_path(servers(:web), tab: "vulnerabilities"), except: data
    assert_english server_path(servers(:web), tab: "docker"), except: data
    assert_english docker_path, except: data
    assert_english docker_path(tab: "cves"), except: data
    assert_english settings_vulnerabilities_path, except: data
    assert_english settings_docker_path, except: data
    assert_english new_settings_score_provider_path, except: data
  end

  test "vulnerabilities of a server and of its images, with the commands to fix them" do
    data = [ ".sidebar-groups", ".account-link", "pre", "code", ".font-mono", ".package-name", "[data-cve]" ]
    { nil => "3.0.15-1~deb12u1", "nginx:1.27" => "3.0.15-1~deb12u1", "redis:7" => nil }.each do |image, fixed|
      servers(:web).server_vulnerabilities.create!(origin: image ? "image" : "host", source: "debian", image: image, cve: "CVE-2024-9143", source_package: "openssl",
                                                   packages: [ "libssl3" ], installed_version: "3.0.14-1~deb12u1", fixed_version: fixed, severity: "high")
    end
    assert_english server_path(servers(:web), tab: "vulnerabilities"), except: data
    assert_english server_path(servers(:web), tab: "vulnerabilities", containers: "1", view: "cves"), except: data
    assert_english vulnerability_path("CVE-2024-9143", server_id: servers(:web).id), except: data
    assert_english vulnerability_path("CVE-2024-9143"), except: data
    assert_english docker_path(tab: "cves"), except: data
  end

  test "the extensions pages" do
    data = [ ".sidebar-groups", ".account-link", "pre", "code", ".font-mono" ]
    assert_english settings_integrations_path, except: data
    Integration.find_or_initialize_by(kind: "uptime_kuma").update!(enabled: true, settings: { "url" => "https://u.test" }, secrets: { "api_key" => "k" })
    Integration.find_or_initialize_by(kind: "ovh").update!(enabled: true, settings: { "application_key" => "a" }, secrets: { "application_secret" => "s", "consumer_key" => "c" })
    # The prompts for an AI are written in the reader's language too.
    assert_english server_path(servers(:web), tab: "monitors"), except: data
    assert_english server_path(servers(:web), tab: "ovh"), except: data
  end

  test "the check finds French" do
    app_settings(:main).update!(default_locale: "fr")
    get root_path
    assert_includes self.class.french_texts(response.body, scope: ".sidebar"), "Vue d'ensemble"
  end

  test "the dictionary of the JavaScript controllers" do
    get root_path
    texts = css_select("script#elio-i18n").first.text
    assert_no_match FRENCH, JSON.parse(texts).to_s
  end
end
