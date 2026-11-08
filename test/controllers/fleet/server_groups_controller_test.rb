require "test_helper"

class ServerGroupsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  test "requires authentication" do
    get server_groups_path
    assert_redirected_to new_user_session_path
  end

  test "lists the groups with their servers" do
    sign_in users(:one)
    get server_groups_path

    assert_response :success
    assert_select "#server-groups li.server-group", 2
    assert_select "##{dom_id(server_groups(:production))}" do
      assert_select "a[href=?]", servers_path(group: server_groups(:production).id), text: "Production"
      assert_select "p", text: "2 serveurs : Database, Web"
      assert_select "a[href=?]", edit_server_group_path(server_groups(:production))
      assert_select "details.actions-menu summary[aria-label=?]", "Actions du groupe « Production »"
      assert_select "details.actions-menu form[action=?][data-confirm-variant=danger] button", server_group_path(server_groups(:production)), text: /Supprimer le groupe/
    end
    assert_select "##{dom_id(server_groups(:staging))} p", text: "Aucun serveur"
  end

  test "shows an empty state" do
    ServerGroup.delete_all
    sign_in users(:one)
    get server_groups_path

    assert_select "p", text: /Aucun groupe/
    assert_select "a[href=?]", new_server_group_path, text: "Créer un groupe"
  end

  test "viewers see the groups without the actions" do
    sign_in users(:viewer)
    get server_groups_path

    assert_select "li.server-group", 2
    assert_select "a[href=?]", new_server_group_path, 0
    assert_select "li.server-group form", 0
  end

  test "the form lists colors and servers" do
    sign_in users(:one)
    get new_server_group_path(server_ids: [ servers(:backup).id ])

    assert_response :success
    assert_select "input[type=radio][name='server_group[color]']", ServerGroup::COLORS.size
    assert_select "input[type=checkbox][name='server_group[server_ids][]']", Server.count
    assert_select "input[type=checkbox][value=?][checked]", servers(:backup).id.to_s
  end

  test "creates a group with servers and logs it" do
    sign_in users(:one)

    assert_difference -> { ServerGroup.count } => 1, -> { Activity.of_kind(:server_group_created).count } => 1 do
      post server_groups_path, params: { server_group: { name: " Clients ", color: "emerald", server_ids: [ "", servers(:web).id, servers(:backup).id ] } }
    end

    group = ServerGroup.find_by!(name: "Clients")
    assert_redirected_to servers_path(group: group.id)
    assert_equal "emerald", group.color
    assert_equal [ servers(:backup), servers(:web) ], group.servers.to_a
    assert_equal({ "group_name" => "Clients", "servers" => 2 }, Activity.last.data)
    assert_equal users(:one), Activity.last.user
  end

  test "re-renders the form when invalid" do
    sign_in users(:one)

    assert_no_difference "ServerGroup.count" do
      post server_groups_path, params: { server_group: { name: "production", color: "red" } }
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: /déjà/
  end

  test "updates the name, color and servers (unchecking every server empties it)" do
    sign_in users(:one)
    group = server_groups(:production)

    patch server_group_path(group), params: { server_group: { name: "Prod", color: "amber", server_ids: [ "" ] } }

    assert_redirected_to servers_path(group: group.id)
    group.reload
    assert_equal [ "Prod", "amber" ], [ group.name, group.color ]
    assert_empty group.servers
    assert Server.exists?(servers(:web).id)
  end

  test "deletes a group but keeps its servers" do
    sign_in users(:one)

    assert_no_difference "Server.count" do
      delete server_group_path(server_groups(:production))
    end

    assert_redirected_to server_groups_path
    assert_response :see_other
    assert_not ServerGroup.exists?(name: "Production")
    assert_equal "Groupe « Production » supprimé", Activity.last.summary
  end

  test "returns 404 for an unknown group" do
    sign_in users(:one)
    get edit_server_group_path(id: 0)
    assert_response :not_found
  end

  test "operators can manage groups, viewers cannot" do
    sign_in users(:operator)
    patch server_group_path(server_groups(:staging)), params: { server_group: { name: "Préprod" } }
    assert_equal "Préprod", server_groups(:staging).reload.name

    sign_in users(:viewer)
    delete server_group_path(server_groups(:staging))
    assert_response :forbidden
    assert ServerGroup.exists?(server_groups(:staging).id)
  end

  test "the expected ports of a group are optional and validated" do
    sign_in users(:one)
    group = server_groups(:production)

    get edit_server_group_path(group)
    assert_select "input[name='server_group[expected_ports]'][placeholder=?]", "22, 80, 443/tcp, 51820/udp"

    patch server_group_path(group), params: { server_group: { name: group.name, color: group.color, expected_ports: "22, 443/tcp" } }
    assert_equal "22, 443/tcp", group.reload.expected_ports

    patch server_group_path(group), params: { server_group: { name: group.name, color: group.color, expected_ports: "22, https" } }
    assert_response :unprocessable_entity
    assert_select "li", text: /Les ports attendus contiennent des valeurs invalides : https/
  end
end
