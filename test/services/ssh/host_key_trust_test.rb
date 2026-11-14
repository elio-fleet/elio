require "test_helper"

class Ssh::HostKeyTrustTest < ActiveSupport::TestCase
  include StubHelpers

  setup do
    @web, @db = servers(:web), servers(:db)
    @old = Ssh::KeyGenerator.generate
    FileUtils.mkdir_p(Ssh::KnownHosts.file.dirname)
    Ssh::KnownHosts.file.write("#{entry(@web, @old.public_key)}\n#{entry(@db, @old.public_key)}\n")
  end

  teardown { Ssh::KnownHosts.file.delete if Ssh::KnownHosts.file.exist? }

  def entry(server, public_key)
    name = server.port == 22 ? server.host : "[#{server.host}]:#{server.port}"
    "#{name} #{public_key.split.first(2).join(" ")}"
  end

  # Each server pins the key given in `keys` in the temporary file it is handed.
  def presenting(keys)
    ->(server, known_hosts_file:, **) { Pathname(known_hosts_file).write("#{entry(server, keys.fetch(server))}\n") }
  end

  test "accepts the shown fingerprints for several servers, and only those" do
    web_key = Ssh::KeyGenerator.generate
    rsa = "ssh-rsa #{[ OpenSSL::PKey::RSA.new(2048).public_key.to_blob ].pack("m0")}"
    rsa_fingerprint = Ssh::KeyGenerator.fingerprint(Base64.strict_decode64(rsa.split.last))

    results = stub_method(Ssh::Check, :call, presenting(@web => web_key.public_key, @db => rsa)) do
      Ssh::HostKeyTrust.call_many([ [ @web, web_key.fingerprint ], [ @db, rsa_fingerprint ] ], user: users(:one))
    end

    assert_equal [ :accepted, :accepted ], results.map(&:status)
    assert_equal [ web_key.fingerprint ], Ssh::KnownHosts.fingerprints(@web.host, @web.port)
    assert_equal [ rsa_fingerprint ], Ssh::KnownHosts.fingerprints(@db.host, @db.port)

    activities = Activity.where(kind: "host_key_changed").order(:id)
    assert_equal [ @web, @db ], activities.map(&:server)
    assert_equal [ users(:one) ], activities.map(&:user).uniq
    assert_equal [ [ "ssh-ed25519", false ], [ "ssh-rsa", true ] ], activities.map { |activity| activity.data.values_at("key_type", "new_algorithm") }
    assert_match "Nouveau type de clé (ssh-rsa)", activities.last.summary
  end

  test "keeps the old pins of a server that presents another key or cannot be read" do
    other = Ssh::KeyGenerator.generate
    check = ->(server, known_hosts_file:, **) { Pathname(known_hosts_file).write("#{entry(server, other.public_key)}\n") if server == @web }

    results = stub_method(Ssh::Check, :call, check) do
      Ssh::HostKeyTrust.call_many([ [ @web, "SHA256:shown" ], [ @db, "SHA256:shown" ] ], user: users(:one))
    end

    assert_equal [ :changed_again, :unreachable ], results.map(&:status)
    assert_equal [ @old.fingerprint ], Ssh::KnownHosts.fingerprints(@web.host, @web.port)
    assert_equal [ @old.fingerprint ], Ssh::KnownHosts.fingerprints(@db.host, @db.port)
    assert_equal 0, Activity.where(kind: "host_key_changed").count
  end

  test "the command to read a key's fingerprint on the server" do
    assert_equal "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub", Ssh::HostKeyTrust.verify_command("ssh-ed25519")
    assert_equal "ssh-keygen -lf /etc/ssh/ssh_host_rsa_key.pub", Ssh::HostKeyTrust.verify_command("ssh-rsa")
    assert_equal "ssh-keygen -lf /etc/ssh/ssh_host_ecdsa_key.pub", Ssh::HostKeyTrust.verify_command("ecdsa-sha2-nistp256")
    assert_equal "ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub", Ssh::HostKeyTrust.verify_command(nil)
  end

  test "a new algorithm is a type none of the pinned keys has" do
    assert Ssh::HostKeyTrust.new_algorithm?("ssh-rsa", [ "ssh-ed25519" ])
    assert_not Ssh::HostKeyTrust.new_algorithm?("ssh-ed25519", [ "ssh-ed25519", "ssh-rsa" ])
    assert_not Ssh::HostKeyTrust.new_algorithm?("ssh-rsa", []), "nothing pinned: nothing to compare with"
    assert_not Ssh::HostKeyTrust.new_algorithm?(nil, [ "ssh-ed25519" ])
  end
end
