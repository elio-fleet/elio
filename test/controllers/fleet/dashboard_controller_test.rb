require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "redirects to sign in when not authenticated" do
    get root_path
    assert_redirected_to new_user_session_path
  end

  test "shows the dashboard when authenticated" do
    sign_in users(:one)
    get root_path
    assert_response :success
    assert_select "h1", "Vue d'ensemble"
  end

  test "there is no public sign up any more" do
    get "/users/sign_up"
    assert_response :not_found

    assert_no_difference "User.count" do
      post "/users", params: { user: { email: "new@example.com", password: "password1234", password_confirmation: "password1234" } }
    end
    assert_response :not_found
  end

  test "the sign in page renders and points to invitations" do
    get new_user_session_path
    assert_response :success
    assert_select "p", text: /Demandez une invitation à un administrateur/
  end

  test "shows the setup checklist until every step is done" do
    sign_in users(:one)
    get root_path

    assert_select "#onboarding" do
      assert_select ".onboarding-step", 5
      assert_select "#onboarding-ssh_key.is-done"
      assert_select "#onboarding-server.is-done"
      assert_select "#onboarding-install_key:not(.is-done)" do
        assert_select ".ssh-setup-hint textarea", text: /authorized_keys/
        assert_select "a[href=?]", server_path(servers(:backup)), text: /Ouvrir Backup pour tester/
      end
    end
  end

  test "the checklist starts with generating the Elio key" do
    SshKey.delete_all
    sign_in users(:one)
    get root_path

    assert_select "#onboarding-ssh_key:not(.is-done) form[action=?] button", ssh_key_path, text: "Générer la clé"
  end

  test "hides the checklist once everything is done" do
    servers(:web).record_ssh_status!(true)
    servers(:web).update_columns(inventoried_at: Time.current)
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(public_keys(:alice).content))
    sign_in users(:one)

    get root_path

    assert_select "#onboarding", 0
  end





  test "has the main navigation with the current page highlighted" do
    sign_in users(:one)

    get root_path
    assert_select "nav.main-nav a[aria-current=page]", text: "Vue d'ensemble"
    assert_select "nav.main-nav a[href=?]", servers_path, text: /Serveurs\s*3/
    assert_select "nav.main-nav a[href=?]", public_keys_path, text: "Clés SSH"
    assert_select ".sidebar a.elio-version", "Elio #{Elio::VERSION}"
    assert_select "nav.main-nav a[href=?]", settings_automations_path, 0
    assert_select "nav.main-nav p.sidebar-section", %w[Sur\ tout\ le\ parc Accès].size # Extensions: only with one enabled
    assert_select "nav.sidebar-groups", 0 # the groups are a filter of the server list

    get server_path(servers(:web))
    assert_select "nav.main-nav a[aria-current=page]", text: /Serveurs/

    get servers_path(group: server_groups(:production).id)
    assert_select "nav.main-nav a[aria-current=page]", text: /Serveurs/

    get public_keys_path
    assert_select "nav.main-nav a[aria-current=page]", text: "Clés SSH"

    sign_in users(:viewer)
    get root_path
    assert_select "nav.main-nav a[href=?]", settings_automations_path, 0
  end

  test "includes the quick search, its button and the confirm dialog when signed in" do
    sign_in users(:one)
    get root_path

    assert_select "body[data-controller~=command-palette]"
    assert_select "dialog#command-palette script[type='application/json']", text: /"label":"Web"/
    assert_select "button.command-palette-button[data-action='command-palette#open']"
    assert_select "dialog#confirm-dialog button[data-confirm-accept]"
    assert_select "#flash[aria-live=polite]"
    assert_select "dialog#command-palette[data-server-actions=true][data-search-url=?]", command_search_path
  end

  test "the quick search offers no server action to a viewer" do
    sign_in users(:viewer)
    get root_path

    assert_select "dialog#command-palette[data-search-url]"
    assert_select "dialog#command-palette[data-server-actions]", 0
  end

  test "no quick search on the sign in page" do
    get new_user_session_path

    assert_select "dialog#command-palette", 0
    assert_select "#flash"
  end

  test "flash messages are rendered as toasts" do
    sign_in users(:one)
    post server_scans_path
    follow_redirect!

    assert_select "#flash .toast.toast-notice[data-controller=toast][role=status]", text: /Scan des clés lancé/ do
      assert_select "button[data-action='toast#dismiss'][aria-label=Fermer]"
    end
  end



  test "shows the recent activity" do
    9.times { |index| travel_to(index.minutes.ago) { Activity.record!(:server_created, server: servers(:web)) } }
    sign_in users(:one)

    get root_path

    assert_select "#recent-activity li.activity", 8
    assert_select "#recent-activity a[href=?]", activities_path, text: "Journal →"
    assert_select "nav.main-nav a[href=?]", activities_path, text: "Journal"
  end

  test "shows the fleet figures" do
    unnamed = Ssh::KeyGenerator.generate.public_key.split(" ").first(2).join(" ")
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(unnamed))
    servers(:web).update_columns(reachable: true)
    sign_in users(:one)

    get root_path

    assert_select "#stat-online .stat-value", "1/3"
    assert_select "#stat-critical .stat-value", "1"
    assert_select "a#stat-critical[href=?]", servers_path(state: "crit")
    assert_select "a#stat-to-watch[href=?]", servers_path(state: "warn")
    assert_select "#stat-vulnerabilities .stat-value", "0"
    assert_select ".stat-tiles a.stat-tile", 4
  end

  test "the serious fixable vulnerabilities, a tile that opens them" do
    servers(:web).server_vulnerabilities.create!(origin: "host", source: "debian", cve: "CVE-2024-6387", source_package: "openssh", installed_version: "1", fixed_version: "2", severity: "high")
    sign_in users(:one)
    get root_path

    assert_select "a#stat-vulnerabilities[href=?] .stat-value.text-crit-ink", vulnerabilities_path(fixable: 1, origin: "host"), text: "1"
  end

  test "the actions: refresh the fleet, and the key scan in the menu" do
    sign_in users(:one)
    get root_path

    assert_select ".page-actions form[action=?] button", server_inventories_path, text: /Actualiser le parc/
    assert_select ".page-actions details.actions-menu form[action=?]", server_scans_path
    assert_select ".page-actions .btn-primary", 0

    sign_in users(:viewer)
    get root_path
    assert_select ".page-actions", 0
  end

  test "an empty fleet shows only the getting started guide" do
    Server.delete_all
    sign_in users(:one)
    get root_path

    assert_select "h1", "Bienvenue dans Elio"
    assert_select "#onboarding"
    assert_select ".stat-tiles", 0
    assert_select "#attention", 0
    assert_select "#recent-activity", 0

    sign_in users(:viewer)
    get root_path
    assert_select "#onboarding", 0
    assert_select ".empty-state", text: /Aucun serveur/
  end

  test "lists the temporary accesses in progress" do
    TemporaryAccess.create!(server: servers(:web), public_key: public_keys(:ci), unix_user: "deploy", key_blob: public_keys(:ci).authorized_key.key,
                            fingerprint: public_keys(:ci).fingerprint, expires_at: 9.minutes.from_now + 30.seconds)
    sign_in users(:one)

    get root_path

    assert_select "#temporary-accesses li.temporary-access" do
      assert_select "p", text: "CI"
      assert_select "a[href=?]", server_path(servers(:web), tab: "keys"), text: "Web"
      assert_select "time[data-controller=relative-time]", text: "expire dans 10 minutes"
    end
  end

  test "lists what needs attention, most serious first" do
    servers(:backup).update_columns(ssh_ok: false)
    servers(:web).update_columns(reachable: true, ssh_ok: true, health_status: "warn", health_reasons: [ { "tone" => "warn", "text" => "Redémarrage requis" } ])
    unnamed = Ssh::KeyGenerator.generate.public_key.split(" ").first(2).join(" ")
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(unnamed))
    sign_in users(:one)

    get root_path

    assert_select "#attention li.attention-item", 5
    assert_equal [ "Critique · 2", "À surveiller · 2", "Pour information · 1" ], css_select("#attention .attention-group").map { |group| group.text.strip }
    assert_select "#attention ul.attention-list:nth-of-type(1) li.attention-item:nth-child(1)[data-tone=crit]", text: /clé d'Elio est refusée.*Backup/m
    assert_select "#attention ul.attention-list:nth-of-type(1) li.attention-item:nth-child(2)[data-tone=crit]", text: /Ne répond plus.*Database/m
    assert_select "#attention li.attention-item[data-tone=crit] a.attention-action[href=?]", server_path(servers(:db)), text: /Tester la connexion/
    assert_select "#attention li.attention-item[data-tone=warn]", text: /Redémarrage requis.*Web/m
    assert_select "#attention li.attention-item[data-tone=neutral]", text: /Pas encore d'inventaire.*Web/m
    assert_select "#attention li.attention-item a.server-chip[href=?]", server_path(servers(:web)), text: "Web"
    assert_select "#attention li.attention-item a.attention-action[href=?]", server_path(servers(:web), tab: "keys"), text: /Voir les clés/
  end

  test "the most serious items first, the others behind See all, each with since when" do
    Server.update_all(reachable: false, ssh_ok: true, inventoried_at: Time.current)
    7.times { |index| Server.create!(name: "node-#{index}", host: "10.0.0.#{index + 10}", username: "elio").update_columns(reachable: true, ssh_ok: true, inventoried_at: Time.current, health_status: "warn", health_reasons: [ { "tone" => "warn", "text" => "Redémarrage requis" } ]) }
    Activity.create!(kind: "server_unreachable", server: servers(:db), created_at: 3.days.ago)
    sign_in users(:one)

    get root_path

    assert_select "#attention li.attention-item", 8
    assert_equal [ "Critique · 3", "À surveiller · 7" ], css_select("#attention .attention-group").map { |group| group.text.strip }
    assert_select "#attention li.attention-item", text: /Database.*apparu il y a 3 jours/m
    assert_select "#attention .attention-more a[href=?]", root_path(attention: "all", anchor: "attention"), text: /Tout voir \(2 de plus\)/

    get root_path(attention: "all")

    assert_select "#attention li.attention-item", 10
    assert_select "#attention .attention-more a[href=?]", root_path(anchor: "attention"), text: "Voir seulement les plus graves"
  end

  test "nothing to report" do
    Server.update_all(reachable: true, ssh_ok: true, inventoried_at: Time.current, health_status: "ok")
    sign_in users(:one)

    get root_path

    assert_select "#attention .empty-state", text: /Rien à signaler/
  end

  test "the groups, with their servers to handle" do
    group = server_groups(:production)
    group.servers.first.update_columns(reachable: false)
    sign_in users(:viewer)

    get root_path

    assert_select "#groups li.group-summary", ServerGroup.count
    assert_select "##{ActionView::RecordIdentifier.dom_id(group, :summary)} details" do
      assert_select "summary", text: /#{group.name}.*1 critique/m
      assert_select "li.group-server", group.servers.count
      assert_select "li.group-server:first-child[data-state=off]", text: /injoignable/
      assert_select "li.group-server a[href=?]", server_path(group.servers.first)
      assert_select "a[href=?]", servers_path(group: group.id), text: /Voir dans la liste des serveurs/
    end
  end

  test "the failed runs of the last day, with a link to all of them" do
    old = BackgroundTask.create!(kind: "inventory", label: "Inventaire ancien", status: "failed", finished_at: 2.days.ago)
    BackgroundTask.create!(kind: "inventory", label: "Inventaire réussi", status: "succeeded", finished_at: 1.hour.ago)
    partial = BackgroundTask.create!(kind: "keys_scan", label: "Scan des clés", status: "partial", finished_at: 1.hour.ago)
    sign_in users(:viewer)

    get root_path

    assert_select "#failed-runs" do
      assert_select "a[href=?]", tasks_path(status: "failed"), text: "Tout voir"
      assert_select "li.failed-run", 1
      assert_select "li.failed-run a[href=?]", task_path(partial), text: "Scan des clés"
      assert_select "a[href=?]", task_path(old), 0
    end

    BackgroundTask.delete_all
    get root_path
    assert_select "#failed-runs", 0
  end

  test "the vulnerabilities tile compares with a week ago once there is a count of that time" do
    ServerVulnerability.delete_all
    sign_in users(:one)
    get root_path
    assert_select "#stat-vulnerabilities", text: /corrigeables, sur le système des serveurs/

    VulnerabilityCount.create!(recorded_on: 7.days.ago.to_date, severity: "high", fixable: 3)
    get root_path
    assert_select "#stat-vulnerabilities", text: /corrigeables · 3 de moins qu'il y a 7 jours/
  end

  test "the temporary accesses only when there are some" do
    sign_in users(:one)
    get root_path
    assert_select "#temporary-accesses", 0
  end
end
