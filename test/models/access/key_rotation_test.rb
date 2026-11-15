require "test_helper"

class KeyRotationTest < ActiveSupport::TestCase
  test "start! creates a pending key and remembers the old one" do
    rotation = KeyRotation.start!(by: users(:one))

    assert_equal ssh_keys(:main), rotation.old_key
    assert rotation.new_key.pending?
    assert_equal 3, rotation.servers_count
    assert rotation.running?
    assert_equal :running, rotation.status
    assert_equal rotation, KeyRotation.in_progress
  end

  test "only one rotation at a time" do
    KeyRotation.start!(by: users(:one))
    assert_raises(KeyRotation::AlreadyRunning) { KeyRotation.start!(by: users(:one)) }
  end

  test "finish! activates the new key and deletes the old one when every server succeeded" do
    old_key_id = ssh_keys(:main).id
    rotation = KeyRotation.start!(by: users(:one))
    rotation.steps.create!(server: servers(:web), server_name: "Web", status: :rotated)

    rotation.finish!

    assert_equal :activated, rotation.status
    assert rotation.new_key.reload.active?
    assert_not SshKey.exists?(old_key_id)
    assert_equal rotation.new_key, SshKey.current
    assert_nil KeyRotation.in_progress
    assert_equal "Clé Elio remplacée sur 3 serveurs", Activity.of_kind(:ssh_key_rotated).sole.summary
  end

  test "finish! keeps both keys when a server failed" do
    rotation = KeyRotation.start!(by: users(:one))
    rotation.steps.create!(server: servers(:db), server_name: "Database", status: :failed, phase: "verify", error_message: "x")

    rotation.finish!

    assert_equal :partial, rotation.status
    assert_equal [ ssh_keys(:main), rotation.new_key ], SshKey.app_keys
    assert_equal 0, Activity.of_kind(:ssh_key_rotated).count
  end

  test "finish!(force: true) activates the new key despite failures" do
    rotation = KeyRotation.start!(by: users(:one))
    rotation.steps.create!(server: servers(:db), server_name: "Database", status: :failed, phase: "install", error_message: "x")

    rotation.finish!(force: true)

    assert_equal :activated, rotation.status
    assert rotation.forced
    assert_equal [ rotation.new_key ], SshKey.app_keys
    assert_equal "Clé Elio remplacée sur 3 serveurs (finalisée malgré 1 échec)", Activity.of_kind(:ssh_key_rotated).sole.summary
  end

  test "phase labels" do
    step = KeyRotationStep.new(phase: "cleanup")
    assert_equal "retrait de l'ancienne clé", step.phase_label
  end

  test "a running rotation without progress for a while is stalled; each step counts as progress" do
    rotation = KeyRotation.start!(by: users(:one))
    assert_not rotation.stalled?

    rotation.update_column(:updated_at, 20.minutes.ago)
    assert rotation.stalled?

    rotation.steps.create!(server: servers(:web), server_name: "Web", status: :rotated)
    assert_not rotation.reload.stalled?

    rotation.update_columns(updated_at: 20.minutes.ago, finished_at: 20.minutes.ago)
    assert_not rotation.stalled?, "a finished rotation is never stalled"
  end
end
