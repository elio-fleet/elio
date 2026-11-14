require "test_helper"

class Ssh::KnownHostsTest < ActiveSupport::TestCase
  setup do
    @file = Pathname(Dir.mktmpdir).join("known_hosts")
    @file.write(<<~HOSTS)
      192.168.1.10 ssh-ed25519 AAAAweb22
      [192.168.1.10]:2222 ssh-ed25519 AAAAweb2222
      db.example.com,10.0.0.2 ssh-ed25519 AAAAdb
      [db.example.com]:22 ssh-rsa AAAAdbrsa
      192.168.1.100 ssh-ed25519 AAAAother
    HOSTS
  end

  teardown { FileUtils.rm_rf(@file.dirname) }

  test "forgets a host on port 22, written with or without brackets" do
    assert_equal 2, Ssh::KnownHosts.forget("db.example.com", 22, file: @file)

    assert_equal [ "AAAAweb22", "AAAAweb2222", "AAAAother" ], @file.readlines.map { |line| line.split.last }
  end

  test "forgets only the given port" do
    assert_equal 1, Ssh::KnownHosts.forget("192.168.1.10", 2222, file: @file)

    assert_includes @file.read, "192.168.1.10 ssh-ed25519 AAAAweb22"
    assert_not_includes @file.read, "AAAAweb2222"
  end

  test "does not touch hosts that only start the same way" do
    Ssh::KnownHosts.forget("192.168.1.10", 22, file: @file)
    assert_includes @file.read, "192.168.1.100 ssh-ed25519 AAAAother"
  end

  test "fingerprints of the pinned keys of a host, like ssh-keygen -l" do
    key = Ssh::KeyGenerator.generate
    blob = key.public_key.split[1]
    @file.write("[web.example.com]:2222 ssh-ed25519 #{blob}\nweb.example.com ssh-ed25519 AAAAport22\n[web.example.com]:2222 ssh-rsa !!notbase64\n")

    assert_equal [ key.fingerprint ], Ssh::KnownHosts.fingerprints("web.example.com", 2222, file: @file)
    assert_equal [], Ssh::KnownHosts.fingerprints("other.example.com", 22, file: @file)
    assert_equal [], Ssh::KnownHosts.fingerprints("web.example.com", 22, file: @file.dirname.join("missing"))
  end

  test "entries tell the type of each pinned key" do
    key = Ssh::KeyGenerator.generate
    @file.write("web.example.com #{key.public_key.split.first(2).join(" ")}\n")

    assert_equal [ Ssh::KnownHosts::Entry.new(type: "ssh-ed25519", fingerprint: key.fingerprint) ], Ssh::KnownHosts.entries("web.example.com", 22, file: @file)
  end

  test "replaces the pins of one host by those of another file, keeping the other hosts" do
    key = Ssh::KeyGenerator.generate
    source = @file.dirname.join("presented")
    source.write("db.example.com,10.0.0.2 #{key.public_key.split.first(2).join(" ")}\n192.168.1.100 ssh-ed25519 AAAAintruder\n")

    entries = Ssh::KnownHosts.replace("db.example.com", 22, source: source, file: @file)

    assert_equal [ key.fingerprint ], entries.map(&:fingerprint)
    assert_not_includes @file.read, "AAAAdb"
    assert_not_includes @file.read, "AAAAintruder", "only the lines of this host are taken from the source"
    assert_includes @file.read, "192.168.1.100 ssh-ed25519 AAAAother"
    assert_includes @file.read, "[192.168.1.10]:2222 ssh-ed25519 AAAAweb2222"
  end

  test "uses the configured file by default, never the project one in tests" do
    assert_not_equal Ssh::Connection::KNOWN_HOSTS_FILE, Ssh::KnownHosts.file
    assert_equal 0, Ssh::KnownHosts.forget("unknown.example.com", 22)
  end

  test "unknown host or missing file" do
    assert_equal 0, Ssh::KnownHosts.forget("unknown.example.com", 22, file: @file)
    assert_equal 0, Ssh::KnownHosts.forget("192.168.1.10", 22, file: @file.dirname.join("missing"))
  end
end
