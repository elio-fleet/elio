require "test_helper"

class Keys::WriteSessionTest < ActiveSupport::TestCase
  include AdvisoryLockHelpers

  setup do
    @known_hosts = Rails.root.join("tmp", "test", "ssh-#{SecureRandom.hex(4)}", "known_hosts")
  end

  teardown { FileUtils.rm_rf(@known_hosts.dirname) }

  def open_session(server, fake) = Keys::WriteSession.open(server, transport: fake, known_hosts_file: @known_hosts) { |ssh| ssh.run_command!("keys.read").stdout }

  test "waits while another change holds the server's lock, then connects" do
    fake = FakeSsh.new(handler: ->(_command) { FakeSsh::Response.new("", "", 0) })
    thread = nil

    with_lock_held_elsewhere(Keys::WriteSession.lock_name(servers(:web))) do
      thread = Thread.new { open_session(servers(:web), fake) }
      sleep 0.3
      assert_empty fake.sessions, "no connection while another change runs on this server"
    end

    thread.join(5)
    assert_equal 1, fake.sessions.size
  end

  test "another server is not held up" do
    fake = FakeSsh.new(handler: ->(_command) { FakeSsh::Response.new("", "", 0) })

    with_lock_held_elsewhere(Keys::WriteSession.lock_name(servers(:web))) do
      open_session(servers(:db), fake)
    end

    assert_equal 1, fake.sessions.size
  end

  test "an open connection is used as it is" do
    ssh = Object.new

    assert_same ssh, Keys::WriteSession.open(servers(:web), ssh: ssh) { |connection| connection }
  end
end
