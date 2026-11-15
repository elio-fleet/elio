require "test_helper"

class HostKeyBatchesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup do
    @web, @db = servers(:web), servers(:db)
    @old = Ssh::KeyGenerator.generate
    @web_key, @db_key = Ssh::KeyGenerator.generate, Ssh::KeyGenerator.generate
    FileUtils.mkdir_p(Ssh::KnownHosts.file.dirname)
    Ssh::KnownHosts.file.write("#{entry(@web, @old)}\n#{entry(@db, @old)}\n")
    Activity.record!(:host_key_mismatch, server: @web, new_fingerprint: @web_key.fingerprint, key_type: "ssh-ed25519", new_algorithm: false)
    Activity.record!(:host_key_mismatch, server: @db, new_fingerprint: @db_key.fingerprint, key_type: "ecdsa-sha2-nistp256", new_algorithm: true)
  end

  teardown { Ssh::KnownHosts.file.delete if Ssh::KnownHosts.file.exist? }

  def entry(server, key)
    name = server.port == 22 ? server.host : "[#{server.host}]:#{server.port}"
    "#{name} #{key.public_key.split.first(2).join(" ")}"
  end

  # Each server pins the key it presents in the temporary file it is handed.
  def presenting(keys)
    ->(server, known_hosts_file:, **) { Pathname(known_hosts_file).write("#{entry(server, keys.fetch(server))}\n") }
  end

  test "requires authentication" do
    get host_key_batch_path
    assert_redirected_to new_user_session_path
  end

  test "lists the changed host keys with the old and new fingerprints" do
    sign_in users(:one)

    get host_key_batch_path

    assert_response :success
    assert_select "h1", "Clés d'hôte changées"
    assert_select "#pending-host-keys tr.pending-host-key", 2
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(@web, :pending_host_key)}" do
      assert_select "input[type=checkbox][name=?][value=?]", "fingerprints[#{@web.id}]", @web_key.fingerprint
      assert_select "td", text: /ssh-ed25519 #{Regexp.escape(@old.fingerprint)}/
      assert_select ".host-key-new", "ssh-ed25519 #{@web_key.fingerprint}"
      assert_select "code", "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub"
      assert_select ".badge", text: "Clé changée"
    end
    assert_select "tr##{ActionView::RecordIdentifier.dom_id(@db, :pending_host_key)} .badge", text: "Nouveau type de clé"
    assert_select "button[data-confirm-variant=danger]", text: "Faire confiance aux empreintes cochées"
  end

  test "says so when no host key changed" do
    Activity.where(kind: "host_key_mismatch").delete_all
    sign_in users(:one)

    get host_key_batch_path

    assert_select ".empty-state", text: /Aucune clé d'hôte changée/
    assert_select "form[action=?]", host_key_batch_path, 0
  end

  test "trusts the checked servers only, each logged" do
    sign_in users(:one)

    stub_method(Ssh::Check, :call, presenting(@web => @web_key, @db => @db_key)) do
      post host_key_batch_path, params: { fingerprints: { @web.id => @web_key.fingerprint } }
    end

    assert_redirected_to host_key_batch_path
    assert_equal "Nouvelle empreinte acceptée pour 1 serveur.", flash[:notice]
    assert_equal [ @web_key.fingerprint ], Ssh::KnownHosts.fingerprints(@web.host, @web.port)
    assert_equal [ @old.fingerprint ], Ssh::KnownHosts.fingerprints(@db.host, @db.port), "not checked: untouched"
    assert_equal [ [ @web, users(:one) ] ], Activity.where(kind: "host_key_changed").map { |activity| [ activity.server, activity.user ] }
    assert_equal [ @db ], PendingHostKey.all.map(&:server)
  end

  test "reports the servers whose key changed again, and ignores servers without a pending change" do
    sign_in users(:one)
    other = Ssh::KeyGenerator.generate

    stub_method(Ssh::Check, :call, presenting(@web => @web_key, @db => other)) do
      post host_key_batch_path, params: { fingerprints: { @web.id => @web_key.fingerprint, @db.id => @db_key.fingerprint, servers(:backup).id => "SHA256:x" } }
    end

    assert_equal "Nouvelle empreinte acceptée pour 1 serveur.", flash[:notice]
    assert_match "Rien n'a été accepté pour 1 serveur", flash[:alert]
    assert_match "Database", flash[:alert]
    assert_equal [ @old.fingerprint ], Ssh::KnownHosts.fingerprints(@db.host, @db.port)
    assert_equal [ @web ], Activity.where(kind: "host_key_changed").map(&:server)
  end

  test "asks to choose a server" do
    sign_in users(:one)
    post host_key_batch_path
    assert_redirected_to host_key_batch_path
    assert_equal "Choisissez au moins un serveur.", flash[:alert]
  end

  test "is forbidden to non admins and changes nothing" do
    sign_in users(:operator)

    get host_key_batch_path
    assert_response :forbidden
    post host_key_batch_path, params: { fingerprints: { @web.id => @web_key.fingerprint } }
    assert_response :forbidden

    assert_equal [ @old.fingerprint ], Ssh::KnownHosts.fingerprints(@web.host, @web.port)
  end
end
