require "test_helper"

class PendingHostKeyTest < ActiveSupport::TestCase
  def mismatch(server, fingerprint, **data)
    Activity.record!(:host_key_mismatch, server: server, new_fingerprint: fingerprint, **data)
  end

  test "servers whose last host key event is a change not accepted yet" do
    mismatch(servers(:web), "SHA256:web", key_type: "ssh-rsa", new_algorithm: true)
    mismatch(servers(:db), "SHA256:db")
    Activity.record!(:host_key_changed, server: servers(:db), new_fingerprint: "SHA256:db")
    mismatch(servers(:backup), "SHA256:first")
    mismatch(servers(:backup), "SHA256:again")

    pending = PendingHostKey.all

    assert_equal [ servers(:web), servers(:backup) ], pending.map(&:server)
    assert_equal [ "SHA256:web", "SHA256:again" ], pending.map(&:new_fingerprint)
    assert_equal [ "ssh-rsa", nil ], pending.map(&:key_type)
    assert_equal [ true, false ], pending.map(&:new_algorithm?)
  end

  test "a server that answered an SSH check since the change is no longer pending" do
    mismatch(servers(:web), "SHA256:web")
    servers(:web).update_columns(ssh_ok: true, ssh_checked_at: 1.minute.from_now)

    assert_empty PendingHostKey.all
  end
end
