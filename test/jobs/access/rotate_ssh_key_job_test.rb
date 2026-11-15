require "test_helper"

class RotateSshKeyJobTest < ActiveJob::TestCase
  include StubHelpers
  include AdvisoryLockHelpers

  # Pretends to talk to the servers; `failures` maps a server name to the phase that fails there.
  class FakeServers
    attr_reader :connections, :installs, :checks, :removals

    def initialize(failures = {})
      @failures = failures
      @connections = []
      @installs = []
      @checks = []
      @removals = []
    end

    # A list of keys: the install (old key first); one key: the new one alone.
    def open(server, key:, **)
      phase = key.is_a?(Array) ? "install" : "verify"
      raise Ssh::Connection::AuthenticationError, "refused" if @failures[server.name] == phase

      @connections << [ server.name, phase ]
      @installs << [ server.name, key.map(&:state) ] if phase == "install"
      yield FakeConnection.new(self, server, key)
    end

    def check(server, key, token)
      @checks << [ server.name, key.state ]
      token
    end

    def remove(server, blob, protected_keys:, ssh:, **)
      @removals << [ server.name, blob, protected_keys.map(&:state), ssh.key.state ]
      ok = @failures[server.name] != "cleanup"
      Keys::AuthorizedKeyRemoval::Result.new(status: ok ? :removed : :error, error_title: "Connexion impossible", error_details: "x")
    end
  end

  FakeConnection = Struct.new(:fake, :server, :key) do
    def run_command!(name, token: nil, **)
      stdout = name == "connection.check" ? fake.check(server, key, token) : "added"
      Ssh::Connection::Result.new(stdout: stdout, stderr: "", exit_status: 0)
    end
  end

  def run_job(rotation, fake, **options)
    stub_method(Ssh::Connection, :open, ->(server, **kw, &block) { fake.open(server, **kw, &block) }) do
      stub_method(Keys::AuthorizedKeyRemoval, :call, ->(server, blob, **kw) { fake.remove(server, blob, **kw) }) do
        RotateSshKeyJob.perform_now(rotation, **options)
      end
    end
  end

  setup do
    @rotation = KeyRotation.start!(by: users(:one))
  end

  test "installs with the old key, then checks and removes the old one on one connection with the new key, then activates" do
    fake = FakeServers.new
    old_blob = ssh_keys(:main).blob

    run_job(@rotation, fake)

    assert_equal %w[Backup Backup Database Database Web Web], fake.connections.map(&:first)
    assert_equal %w[install verify] * 3, fake.connections.map(&:last)
    assert fake.installs.all? { |_, states| states == %w[active pending] }
    assert fake.checks.all? { |_, state| state == "pending" }
    assert fake.removals.all? { |_, blob, protected, key| blob == old_blob && protected == [ "pending" ] && key == "pending" }
    assert_equal %w[rotated] * 3, @rotation.steps.reload.map(&:status)
    assert_equal :activated, @rotation.reload.status
    assert_equal [ @rotation.new_key ], SshKey.app_keys
  end

  test "records the phase that failed and keeps both keys" do
    fake = FakeServers.new("Backup" => "install", "Database" => "verify", "Web" => "cleanup")

    run_job(@rotation, fake)

    assert_equal [ [ "Backup", "install" ], [ "Database", "verify" ], [ "Web", "cleanup" ] ], @rotation.steps.reload.map { |s| [ s.server_name, s.phase ] }
    assert_equal [ %w[Web], %w[Web] ], [ fake.checks.map(&:first), fake.removals.map(&:first) ]
    assert_equal :partial, @rotation.reload.status
    assert_equal 2, SshKey.app_keys.size
  end

  test "retrying redoes only the failed servers" do
    run_job(@rotation, FakeServers.new("Database" => "verify"))
    fake = FakeServers.new

    run_job(@rotation, fake, retry_failed: true)

    assert_equal [ "Database" ], fake.installs.map(&:first)
    assert_equal %w[rotated] * 3, @rotation.steps.reload.map(&:status)
    assert_equal :activated, @rotation.reload.status
  end

  test "an interrupted run resumes with the servers not done yet, and a server added meanwhile is not forgotten" do
    @rotation.steps.create!(server: servers(:backup), server_name: "Backup", status: :rotated)
    added = Server.create!(name: "Added", host: "192.0.2.50", username: "root")
    fake = FakeServers.new

    run_job(@rotation, fake)

    assert_equal %w[Added Database Web], fake.installs.map(&:first)
    assert_equal 4, @rotation.reload.servers_count
    assert_equal :activated, @rotation.status
    assert @rotation.steps.find_by!(server: added).rotated?
  end

  test "does nothing while another run of the rotation holds its lock" do
    fake = FakeServers.new

    with_lock_held_elsewhere("key_rotation:#{@rotation.id}") { run_job(@rotation, fake) }

    assert_empty fake.connections
    assert @rotation.reload.running?
  end

  test "an activated rotation is never run again" do
    run_job(@rotation, FakeServers.new)
    fake = FakeServers.new

    run_job(@rotation, fake)

    assert_empty fake.connections
  end
end
