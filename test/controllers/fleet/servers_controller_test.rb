require "test_helper"

class ServersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include ActiveJob::TestHelper
  include ActionView::RecordIdentifier

  def valid_params
    { server: { name: "Staging", host: "staging.example.com", port: 2222, username: "deploy" } }
  end

  test "the form lets choose the groups, only when there are some" do
    sign_in users(:one)

    get edit_server_path(servers(:web))
    assert_select "input[type=checkbox][name='server[server_group_ids][]'][value=?][checked]", server_groups(:production).id.to_s
    assert_select "input[type=checkbox][name='server[server_group_ids][]'][value=?]:not([checked])", server_groups(:staging).id.to_s

    ServerGroup.delete_all
    get new_server_path
    assert_select "input[name='server[server_group_ids][]']", 0
  end

  test "create and update set the server groups, and an empty choice clears them" do
    sign_in users(:one)

    post servers_path, params: { server: valid_params[:server].merge(server_group_ids: [ "", server_groups(:staging).id ]) }
    server = Server.find_by!(name: "Staging")
    assert_equal [ server_groups(:staging) ], server.server_groups.to_a

    patch server_path(server), params: { server: { server_group_ids: [ "" ] } }
    assert_redirected_to server_path(server)
    assert_empty server.reload.server_groups
    assert_equal 0, Activity.of_kind(:server_updated).count, "changing groups is not a connection change"
  end

  test "the server page shows its groups" do
    sign_in users(:one)
    stub_method(Servers::Ping, :reachable?, true) { get server_path(servers(:web)) }

    assert_select ".server-groups a.group-tag[href=?]", servers_path(group: server_groups(:production).id), text: "Production"
  end

  test "new redirects to sign in when not authenticated" do
    get new_server_path
    assert_redirected_to new_user_session_path
  end

  test "create redirects to sign in when not authenticated" do
    assert_no_difference "Server.count" do
      post servers_path, params: valid_params
    end
    assert_redirected_to new_user_session_path
  end

  test "new renders the form with port 22 by default" do
    sign_in users(:one)
    get new_server_path

    assert_response :success
    assert_select "form[action=?]", servers_path do
      assert_select "input[name='server[name]']"
      assert_select "input[name='server[host]']"
      assert_select "input[name='server[port]'][value='22']"
      assert_select "input[name='server[username]']"
      assert_select "input[name='server[password]']", 0
    end
  end

  test "create saves the server and redirects to its page" do
    sign_in users(:one)

    assert_difference "Server.count", 1 do
      post servers_path, params: valid_params
    end

    server = Server.find_by!(name: "Staging")
    assert_equal [ "staging.example.com", 2222, "deploy" ], [ server.host, server.port, server.username ]
    assert_redirected_to server_path(server)
    follow_redirect!
    assert_select "#flash", text: /Le serveur « Staging » a été ajouté./
  end

  test "create re-renders the form with errors when invalid" do
    sign_in users(:one)

    assert_no_difference "Server.count" do
      post servers_path, params: { server: { name: "", host: "not a host", port: 0, username: "" } }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", minimum: 4
  end

  test "create rejects a duplicate name" do
    sign_in users(:one)

    assert_no_difference "Server.count" do
      post servers_path, params: { server: valid_params[:server].merge(name: "web") }
    end
    assert_response :unprocessable_entity
  end

  test "create rejects requests without server params" do
    sign_in users(:one)
    post servers_path, params: {}
    assert_response :bad_request
  end

  test "edit and update redirect to sign in when not authenticated" do
    get edit_server_path(servers(:web))
    assert_redirected_to new_user_session_path

    patch server_path(servers(:web)), params: { server: { name: "Hacked" } }
    assert_redirected_to new_user_session_path
    assert_equal "Web", servers(:web).reload.name
  end

  test "edit renders the form prefilled" do
    sign_in users(:one)
    get edit_server_path(servers(:web))

    assert_response :success
    assert_select "form[action=?]", server_path(servers(:web)) do
      assert_select "input[name='server[name]'][value='Web']"
      assert_select "input[name='server[host]'][value='192.168.1.10']"
      assert_select "input[name='server[port]'][value='22']"
      assert_select "input[name='server[username]'][value='deploy']"
      assert_select "input[type=submit][value='Enregistrer']"
    end
  end

  test "edit returns 404 for an unknown server" do
    sign_in users(:one)
    get edit_server_path(id: 0)
    assert_response :not_found
  end

  test "update changes the server and redirects to the dashboard" do
    sign_in users(:one)

    patch server_path(servers(:web)), params: { server: { name: "Web prod", host: "web.example.com", port: 2200, username: "ops" } }

    server = servers(:web).reload
    assert_equal [ "Web prod", "web.example.com", 2200, "ops" ], [ server.name, server.host, server.port, server.username ]
    assert_redirected_to server_path(server)
    assert_equal "Le serveur « Web prod » a été modifié.", flash[:notice]
  end

  test "update saves the server's own thresholds and recomputes its health; the form shows the inherited ones" do
    server = servers(:web)
    server.inventory_snapshots.create!(category: "health", status: "ok", data: { "memory" => { "used_percent" => 60 } }, collected_at: Time.current, checked_at: Time.current)
    server.refresh_health!
    server_groups(:production).update!(health_thresholds: { "memory_warn" => 85 })
    sign_in users(:one)

    get edit_server_path(server)
    assert_select "input[name='server[health_thresholds][memory_warn]'][placeholder='85']"
    assert_select "input[name='server[health_thresholds][disk_warn]'][placeholder='80']"

    patch server_path(server), params: { server: { name: "Web", health_thresholds: { memory_warn: "50", memory_crit: "" } } }

    assert_redirected_to server_path(server)
    assert_equal [ { "memory_warn" => 50 }, "warn" ], [ server.reload.health_thresholds, server.health_status ]
    assert_equal %w[health_thresholds], Activity.of_kind(:server_updated).sole.data["changed"]

    patch server_path(server), params: { server: { health_thresholds: { memory_warn: "" }, server_group_ids: [ "" ] } }
    assert_equal [ {}, "ok" ], [ server.reload.health_thresholds, server.health_status ]
  end

  test "update ignores a password param" do
    sign_in users(:one)

    patch server_path(servers(:web)), params: { server: { name: "Web 2", password: "ignored" } }

    assert_redirected_to server_path(servers(:web))
    assert_equal "Web 2", servers(:web).reload.name
    assert_not servers(:web).has_attribute?(:password)
  end

  test "update re-renders the form with errors when invalid" do
    sign_in users(:one)

    patch server_path(servers(:web)), params: { server: { name: "", host: "not a host" } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", minimum: 2
    assert_select "h1", text: "Modifier « Web »"
    assert_equal "Web", servers(:web).reload.name
  end

  test "update rejects a name already used by another server" do
    sign_in users(:one)

    patch server_path(servers(:web)), params: { server: { name: "database" } }

    assert_response :unprocessable_entity
    assert_equal "Web", servers(:web).reload.name
  end

  test "show redirects to sign in when not authenticated" do
    get server_path(servers(:web))
    assert_redirected_to new_user_session_path
  end

  test "show displays the server and checks its port and SSH access on display" do
    sign_in users(:one)
    server = servers(:web)

    get server_path(server)

    assert_response :success
    assert_select "h1", "Web"
    assert_select ".page-subtitle .server-summary", text: /\Adeploy@192\.168\.1\.10:22/
    assert_select "a[href=?]", edit_server_path(server)
    assert_select "#server-health" do
      assert_select "turbo-frame##{dom_id(server, :reachability)}[loading=lazy][src=?]", server_ping_path(server) do
        assert_select ".server-status", text: "En ligne" # last known state while checking
        assert_select ".health-checking", text: /Vérification/
      end
      assert_select "turbo-frame##{dom_id(server, :ssh_check)}[loading=lazy][src=?]", server_ssh_check_path(server) do
        assert_select ".ssh-status", text: "—"
        assert_select ".health-checking"
      end
    end
    assert_select "#server-status", 0
    assert_select "#server-ssh", 0
  end

  test "show returns 404 for an unknown server" do
    sign_in users(:one)
    get server_path(id: 0)
    assert_response :not_found
  end

  test "logs the created server" do
    sign_in users(:one)

    post servers_path, params: valid_params

    activity = Activity.of_kind(:server_created).sole
    assert_equal [ Server.find_by!(name: "Staging"), users(:one) ], [ activity.server, activity.user ]
    assert_equal "deploy@staging.example.com:2222", activity.data["address"]
  end

  test "logs an update only when something changed" do
    sign_in users(:one)

    patch server_path(servers(:web)), params: { server: { name: "Web" } }
    assert_equal 0, Activity.count

    patch server_path(servers(:web)), params: { server: { host: "10.0.0.9", port: 2200 } }
    assert_equal %w[host port], Activity.of_kind(:server_updated).sole.data["changed"]

    patch server_path(servers(:web)), params: { server: { expected_ports: "8081/tcp" } }
    assert_equal "8081/tcp", servers(:web).reload.expected_ports
    assert_equal %w[expected_ports], Activity.of_kind(:server_updated).order(:id).last.data["changed"]
  end

  test "expected containers: edited with the server, its Docker state computed again" do
    sign_in users(:one)
    server = servers(:web)
    server.inventory_snapshots.create!(category: "docker", status: "ok", collected_at: Time.current, checked_at: Time.current,
                                       data: { "docker" => "ok", "images" => [], "containers" => [ { "name" => "web", "state" => "running" } ] })
    server.update_columns(health_status: "ok", docker_status: "ok", docker_reasons: [])

    get edit_server_path(server)
    assert_select "input[name='server[expected_containers]'][placeholder=?]", "nginx, shop-db-1"
    patch server_path(server), params: { server: { expected_containers: "web, db" } }
    assert_equal [ "crit", [ "Conteneur attendu db arrêté ou absent" ] ], [ server.reload.docker_status, server.docker_reason_texts ]
    assert_equal %w[expected_containers], Activity.of_kind(:server_updated).sole.data["changed"]

    patch server_path(server), params: { server: { expected_containers: "web, /db" } }
    assert_response :unprocessable_entity
    assert_select "#error_explanation", text: %r{/db}
  end

  test "the server page shows its history" do
    Activity.record!(:key_added, server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy")
    Activity.record!(:key_added, server: servers(:db), public_key: public_keys(:alice), unix_user: "admin")
    sign_in users(:one)

    get server_path(servers(:web), tab: "journal")

    assert_select "#server-activity li.activity", 1
    assert_select "#server-journal a[href=?]", activities_path(server_id: servers(:web).id), text: /journal du parc/
  end

  test "destroy requires authentication" do
    delete server_path(servers(:web))
    assert_redirected_to new_user_session_path
    assert Server.exists?(servers(:web).id)
  end

  test "destroy returns 404 for an unknown server" do
    sign_in users(:one)
    delete server_path(id: 0)
    assert_response :not_found
  end

  test "destroy removes the server, logs it and forgets its host key" do
    sign_in users(:one)
    server = servers(:web)
    TemporaryAccess.create!(server: server, public_key: public_keys(:ci), unix_user: "deploy", key_blob: public_keys(:ci).authorized_key.key,
                            fingerprint: public_keys(:ci).fingerprint, expires_at: 9.minutes.from_now)
    previous = Activity.record!(:key_added, server: server, public_key: public_keys(:alice), unix_user: "deploy")
    forgotten = []

    stub_method(Ssh::KnownHosts, :forget, ->(host, port, **) { forgotten << [ host, port ] }) do
      delete server_path(server)
    end

    assert_not Server.exists?(server.id)
    assert_redirected_to servers_path
    assert_response :see_other
    assert_equal "Le serveur « Web » a été supprimé d'Elio. Les clés installées dessus n'ont pas été retirées.", flash[:notice]
    assert_equal [ [ "192.168.1.10", 22 ] ], forgotten

    deleted = Activity.of_kind(:server_deleted).sole
    assert_equal [ users(:one), "Web", "deploy@192.168.1.10:22", 1 ],
                 [ deleted.user, deleted.server_name, deleted.data["address"], deleted.data["active_temporary_accesses"] ]
    assert_equal "« Alice » ajoutée sur « Web »", previous.reload.summary
  end

  test "destroy keeps the host key when another server uses the same address" do
    sign_in users(:one)
    Server.create!(name: "Web bis", host: "192.168.1.10", port: 22, username: "root")
    forgotten = []

    stub_method(Ssh::KnownHosts, :forget, ->(*args, **) { forgotten << args }) do
      delete server_path(servers(:web))
    end

    assert_empty forgotten
  end

  test "the server page and the edit page offer to delete the server, with a warning" do
    TemporaryAccess.create!(server: servers(:web), public_key: public_keys(:ci), unix_user: "deploy", key_blob: public_keys(:ci).authorized_key.key,
                            fingerprint: public_keys(:ci).fingerprint, expires_at: 9.minutes.from_now)
    sign_in users(:one)

    get server_path(servers(:web))
    assert_select "form[action=?][data-confirm-variant=danger] input[name=_method][value=delete]", server_path(servers(:web))
    assert_select "form[action=?][data-turbo-confirm*='pas retirées'][data-turbo-confirm*='1 accès temporaire']", server_path(servers(:web))

    get edit_server_path(servers(:web))
    assert_select ".page-actions details.actions-menu form[action=?][data-confirm-variant=danger] button.delete-server", server_path(servers(:web)), text: /Supprimer le serveur/
    assert_select ".page-actions details.actions-menu form[action=?][data-turbo-confirm*='1 accès temporaire']", server_path(servers(:web))
  end

  test "the server page has one tab per section, the overview by default" do
    servers(:web).inventory_snapshots.create!(category: "packages", status: "ok", data: { "total" => 412 }, collected_at: Time.current, checked_at: Time.current)
    sign_in users(:viewer)

    get server_path(servers(:web))
    assert_equal %w[overview vulnerabilities packages services firewall schedules keys journal], css_select("nav.server-tabs .tabs-bar > a").map { |tab| tab["data-tab"] }
    assert_select "nav.server-tabs a[aria-current=page][data-tab=overview][href=?]", server_path(servers(:web), tab: "overview")
    assert_select "nav.server-tabs a[data-tab=packages][href=?]", server_path(servers(:web), tab: "packages"), text: "Mises à jour"
    assert_select "#server-health-details"
    assert_select "#server-system"
    assert_select "#server-packages", 0

    get server_path(servers(:web), tab: "firewall")
    assert_select "nav.server-tabs a[aria-current=page][data-tab=firewall]"
    assert_select "#server-ports"
    assert_select "#server-health-details", 0

    get server_path(servers(:web), tab: "ports")
    assert_redirected_to server_path(servers(:web), tab: "firewall")
    get server_path(servers(:web), tab: "notes")
    assert_redirected_to server_path(servers(:web), tab: "journal")

    get server_path(servers(:web), tab: "nope")
    assert_select "nav.server-tabs a[aria-current=page][data-tab=overview]"
  end

  test "a new server gets its first inventory in the background" do
    sign_in users(:one)

    post servers_path, params: valid_params

    assert_enqueued_with(job: Inventory::FirstCollectJob, args: [ Server.find_by!(name: "Staging") ])
  end

  test "a server already added (same host, port and user) is refused" do
    sign_in users(:one)
    db = servers(:db)

    assert_no_difference "Server.count" do
      post servers_path, params: { server: { name: "Copy", host: db.host.upcase, port: db.port, username: db.username } }
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: /déjà utilisé par un autre serveur/
  end

  test "duplicating a server fills in its port, user and groups, not its name nor its host" do
    sign_in users(:one)
    db = servers(:db)
    db.update!(server_group_ids: [ server_groups(:staging).id ])

    get new_server_path(from: db.id)

    assert_response :success
    assert_select "input[name='server[name]']:not([value])"
    assert_select "input[name='server[host]']:not([value])"
    assert_select "input[name='server[port]'][value=?]", db.port.to_s
    assert_select "input[name='server[username]'][value=?]", db.username
    assert_select "input[name='server[server_group_ids][]'][value=?][checked]", server_groups(:staging).id.to_s
    assert_select ".page-subtitle", text: /Copie de « #{db.name} »/

    get new_server_path(from: 0)
    assert_select "input[name='server[port]'][value='22']"
  end

  test "the server page and its edit page offer to duplicate it" do
    sign_in users(:one)

    stub_method(Servers::Ping, :reachable?, true) { get server_path(servers(:web)) }
    assert_select "a[href=?]", new_server_path(from: servers(:web).id), text: "Dupliquer"

    get edit_server_path(servers(:web))
    assert_select "a[href=?]", new_server_path(from: servers(:web).id), text: "Dupliquer"
  end

  test "testing the connection tries the form values without saving" do
    sign_in users(:one)
    tried = nil
    ok = Ssh::Check::Result.new(success: true, message: "ok", details: "deploy@staging.example.com a répondu")

    check = lambda do |server, **|
      tried = server
      ok
    end

    assert_no_difference "Server.count" do
      stub_method(Ssh::Check, :call, check) do
        post test_connection_servers_path, params: valid_params, as: :turbo_stream
      end
    end

    assert_response :success
    assert_equal [ "staging.example.com", 2222, "deploy", false ], [ tried.host, tried.port, tried.username, tried.persisted? ]
    assert_select "turbo-stream[action=replace][target=server-connection-test]"
    assert_select ".connection-test-result[data-result=good]", text: /Elio peut se connecter à ce serveur/
  end

  test "testing the connection tells the root access Elio will have, and what stays partial without it" do
    sign_in users(:one)
    asked = nil
    check = lambda do |_server, privilege: false|
      asked = privilege
      Ssh::Check::Result.new(success: true, message: "ok", details: "ok", privilege: "none")
    end

    stub_method(Ssh::Check, :call, check) do
      post test_connection_servers_path, params: valid_params, as: :turbo_stream
    end

    assert asked
    assert_select ".connection-test-privilege[data-privilege=none]", text: /Accès root : aucun.*ne seront lus qu'en partie/m

    stub_method(Ssh::Check, :call, Ssh::Check::Result.new(success: true, message: "ok", details: "ok", privilege: "sudo")) do
      post test_connection_servers_path, params: valid_params, as: :turbo_stream
    end
    assert_select ".connection-test-privilege[data-privilege=sudo]", text: "Accès root : sudo sans mot de passe."
  end

  test "testing the connection from the edit form (sent as PATCH) shows a refused key and how to install it" do
    sign_in users(:one)
    refused = Ssh::Check::Result.new(success: false, message: "Authentification refusée", details: "refusée", reason: :key_refused)

    stub_method(Ssh::Check, :call, refused) do
      patch test_connection_servers_path, params: { server: { name: "Web", host: "192.168.1.10", port: 22, username: "deploy" } }, as: :turbo_stream
    end

    assert_response :success
    assert_select ".connection-test-result[data-result=crit]", text: /Authentification refusée/
    assert_select ".ssh-setup-hint"
  end

  test "testing the connection with invalid fields says so without connecting" do
    sign_in users(:one)

    stub_method(Ssh::Check, :call, ->(*) { flunk "no connection with invalid fields" }) do
      post test_connection_servers_path, params: { server: { host: "not a host", port: 22, username: "root" } }, as: :turbo_stream
    end

    assert_select ".connection-test-result[data-result=crit]", text: /Vérifiez les champs de connexion/
  end

  test "the form has a button to test the connection, after the save button" do
    sign_in users(:one)
    get new_server_path

    assert_select "form input[type=submit] ~ button.test-connection[formaction=?][formnovalidate]", test_connection_servers_path
    assert_select "#server-connection-test"
  end
end
