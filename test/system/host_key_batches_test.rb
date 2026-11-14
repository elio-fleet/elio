require "application_system_test_case"

class HostKeyBatchesTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup do
    servers(:backup).update_columns(port: servers(:backup).port + 1) # its own pins
    @keys = { servers(:web) => Ssh::KeyGenerator.generate, servers(:backup) => Ssh::KeyGenerator.generate }
    @keys.each { |server, key| Activity.record!(:host_key_mismatch, server: server, new_fingerprint: key.fingerprint, key_type: "ssh-ed25519", new_algorithm: false) }
    keys = @keys
    stub_method_until_teardown(Ssh::Check, :call, lambda do |server, known_hosts_file:, **|
      Pathname(known_hosts_file).write("[#{server.host}]:#{server.port} #{keys.fetch(server).public_key.split.first(2).join(" ")}\n")
    end)
    sign_in users(:one)
  end

  teardown { Ssh::KnownHosts.file.delete if Ssh::KnownHosts.file.exist? }

  test "trusting the new host keys of several servers after a reinstall" do
    visit host_key_batch_path
    assert_selector "#pending-host-keys tr.pending-host-key", count: 2

    click_on "Tous"
    accept_app_confirm { click_on "Faire confiance aux empreintes cochées" }

    assert_selector "#flash .toast", text: "Nouvelles empreintes acceptées pour 2 serveurs."
    assert_selector ".empty-state", text: "Aucune clé d'hôte changée"
    @keys.each do |server, key|
      assert_equal [ key.fingerprint ], Ssh::KnownHosts.fingerprints(server.host, server.port)
    end
  end
end
