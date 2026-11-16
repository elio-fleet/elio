require "application_system_test_case"

class ServerGroupsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:one) }

  test "creating a group and filtering the servers with it" do
    visit servers_path
    fleet_action "Gérer les groupes"
    click_on "Nouveau groupe"

    fill_in "Nom", with: "Clients"
    find("label", text: "Vert").click
    check "server_group_server_ids_#{servers(:backup).id}", allow_label_click: true
    click_on "Créer le groupe"

    assert_selector "#flash .toast", text: "Le groupe « Clients » a été créé."
    assert_selector ".group-filter option[selected]", text: "Clients"
    assert_selector "#servers tbody tr", count: 1
    assert_selector "#servers tbody tr", text: "Backup"

    find(".group-filter select").select("Tous les groupes")
    assert_selector "#servers tbody tr", count: Server.count
  end

  test "unfolding a group on the overview shows its servers" do
    servers(:db).update_columns(reachable: false)
    visit root_path

    within("#groups") do
      assert_no_selector "li.group-server"
      find("summary", text: "Production").click
      assert_selector "li.group-server", count: 2
      assert_selector "li.group-server:first-child", text: /Database.*injoignable/m
      click_on "Web"
    end

    assert_current_path server_path(servers(:web))
  end

  test "checking a whole group in the public_key's bulk form" do
    visit public_key_path(public_keys(:alice))

    within("#bulk-authorize") do
      assert_selector ".picker-count", text: "0 serveur coché"
      click_on "Production"
      assert_selector ".picker-count", text: "2 serveurs cochés"
      check "Backup"
      assert_selector ".picker-count", text: "3 serveurs cochés"
      uncheck "Backup"
      assert_checked_field "server_ids_#{servers(:web).id}", visible: :all
      assert_checked_field "server_ids_#{servers(:db).id}", visible: :all
      assert_no_checked_field "server_ids_#{servers(:backup).id}", visible: :all

      click_on "Production"
      assert_no_checked_field "server_ids_#{servers(:web).id}", visible: :all
    end
  end
end
