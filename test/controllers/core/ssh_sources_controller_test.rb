require "test_helper"

class SshSourcesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include PortHelpers

  setup { sign_in users(:one) }

  test "the general settings list the sources, with the warning about Elio's address" do
    get settings_path
    assert_select "#firewall-settings .ssh-sources-warning", text: /adresse d'Elio/
    assert_select "#firewall-settings", text: /Aucune source/

    SshSource.create!(name: "Elio", cidr: "203.0.113.5")
    get settings_path
    assert_select "#firewall-settings li.ssh-source[data-name=Elio]", text: /203\.0\.113\.5/
  end

  test "adds a source, refuses an invalid one" do
    post settings_ssh_sources_path, params: { ssh_source: { name: "Coolify", cidr: "203.0.113.6" } }
    assert_redirected_to settings_path(anchor: "firewall-settings")
    assert_equal "Source SSH Coolify ajoutée.", flash[:notice]
    assert_equal "203.0.113.6", SshSource.sole.cidr

    assert_no_difference -> { SshSource.count } do
      post settings_ssh_sources_path, params: { ssh_source: { name: "Bad", cidr: "not an ip" } }
    end
    assert_predicate flash[:alert], :present?
  end

  test "deletes a source, and the groups no longer choose it; reorders" do
    elio = SshSource.create!(name: "Elio", cidr: "203.0.113.5", position: 0)
    office = SshSource.create!(name: "Office", cidr: "198.51.100.0/24", position: 1)
    server_groups(:production).update!(ssh_source_ids: [ elio.id, office.id ])

    patch move_settings_ssh_source_path(office, direction: "up")
    assert_equal %w[Office Elio], SshSource.ordered.pluck(:name)

    delete settings_ssh_source_path(elio)
    assert_redirected_to settings_path(anchor: "firewall-settings")
    assert_equal [ office.id ], server_groups(:production).reload.ssh_source_ids
  end

  test "a group chooses its sources; the Firewall tab says where SSH is open from" do
    elio = SshSource.create!(name: "Elio", cidr: "203.0.113.5")
    get edit_server_group_path(server_groups(:production))
    assert_select ".group-ssh-sources input[type=checkbox][value=?]", elio.id.to_s

    patch server_group_path(server_groups(:production)), params: { server_group: { name: "Production", color: server_groups(:production).color, ssh_source_ids: [ "", elio.id ] } }
    assert_equal [ elio.id ], server_groups(:production).reload.ssh_source_ids

    record_ports(servers(:db))
    get server_path(servers(:db), tab: "firewall")
    assert_select ".ssh-sources-summary", text: /SSH limité à : Elio.*choix de Production/m
    assert_select "#server-firewall-suggested textarea", text: /sudo ufw allow from 203\.0\.113\.5 to any port \d+ proto tcp comment 'ssh \(Elio\)'/
    assert_select ".server-prompt[data-kind=firewall] textarea", text: /## Sources autorisées pour le SSH\n.*\n- Elio \(203\.0\.113\.5\)/

    SshSource.delete_all
    get server_path(servers(:db), tab: "firewall")
    assert_select ".ssh-sources-summary", text: /SSH ouvert à tous/
  end
end
