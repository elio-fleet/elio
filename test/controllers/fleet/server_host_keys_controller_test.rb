require "test_helper"

class ServerHostKeysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup do
    @server = servers(:web)
    @old = Ssh::KeyGenerator.generate
    @new = Ssh::KeyGenerator.generate
    FileUtils.mkdir_p(Ssh::KnownHosts.file.dirname)
    Ssh::KnownHosts.file.write("#{entry(@old)}\n10.9.9.9 #{@other = Ssh::KeyGenerator.generate.public_key.split.first(2).join(" ")}\n")
  end

  teardown { Ssh::KnownHosts.file.delete if Ssh::KnownHosts.file.exist? }

  # Mimics net-ssh pinning whatever key the server presents (accept_new) in
  # the known_hosts file it is given (a temporary one, never the real pins).
  def presenting(key)
    lambda do |server, known_hosts_file:, **|
      assert_not_equal Ssh::KnownHosts.file, Pathname(known_hosts_file)
      Pathname(known_hosts_file).write("#{entry(key)}\n")
      Ssh::Check::Result.new(success: true, message: "ok", details: "ok")
    end
  end

  def entry(key)
    name = @server.port == 22 ? @server.host : "[#{@server.host}]:#{@server.port}"
    "#{name} #{key.public_key.split.first(2).join(" ")}"
  end

  test "requires authentication" do
    post server_host_key_path(@server), params: { fingerprint: @new.fingerprint }
    assert_redirected_to new_user_session_path
  end

  test "replaces the pinned key when the server presents the expected one" do
    sign_in users(:one)

    stub_method(Ssh::Check, :call, presenting(@new)) do
      post server_host_key_path(@server), params: { fingerprint: @new.fingerprint }
    end

    assert_redirected_to server_path(@server)
    assert_match "Nouvelle empreinte acceptée", flash[:notice]
    assert_equal [ @new.fingerprint ], Ssh::KnownHosts.fingerprints(@server.host, @server.port)
    assert_includes Ssh::KnownHosts.file.read, "10.9.9.9 #{@other}", "other hosts are kept"

    activity = Activity.last
    assert_equal "host_key_changed", activity.kind
    assert_equal users(:one), activity.user
    assert_equal @server, activity.server
    assert_equal({ "new_fingerprint" => @new.fingerprint, "previous_fingerprints" => [ @old.fingerprint ], "key_type" => "ssh-ed25519", "new_algorithm" => false },
                 activity.data.slice("new_fingerprint", "previous_fingerprints", "key_type", "new_algorithm"))
  end

  test "keeps the old pin when the server cannot be contacted" do
    sign_in users(:one)

    assert_no_difference "Activity.count" do
      stub_method(Ssh::Check, :call, ->(*, **) { Ssh::Check::Result.new(success: false, message: "x", details: "x") }) do
        post server_host_key_path(@server), params: { fingerprint: @new.fingerprint }
      end
    end

    assert_match "Impossible de contacter le serveur", flash[:alert]
    assert_equal [ @old.fingerprint ], Ssh::KnownHosts.fingerprints(@server.host, @server.port)
  end

  test "pins nothing when the server presents yet another key" do
    sign_in users(:one)
    third = Ssh::KeyGenerator.generate

    assert_no_difference "Activity.count" do
      stub_method(Ssh::Check, :call, presenting(third)) do
        post server_host_key_path(@server), params: { fingerprint: @new.fingerprint }
      end
    end

    assert_redirected_to server_path(@server)
    assert_match "ne présente plus l'empreinte affichée", flash[:alert]
    assert_equal [ @old.fingerprint ], Ssh::KnownHosts.fingerprints(@server.host, @server.port), "the old pin stays: the server stays blocked"
  end

  test "is forbidden to non admins and changes nothing" do
    sign_in users(:operator)

    post server_host_key_path(@server), params: { fingerprint: @new.fingerprint }

    assert_response :forbidden
    assert_equal [ @old.fingerprint ], Ssh::KnownHosts.fingerprints(@server.host, @server.port)
  end

  test "requires the fingerprint" do
    sign_in users(:one)
    post server_host_key_path(@server)
    assert_response :bad_request
  end
end
