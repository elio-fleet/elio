require "test_helper"

class ServersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
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
    assert_select "nav.server-tabs a[aria-current=page][data-tab=overview][href=?]", server_path(servers(:web))
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
end
