require "test_helper"

class KeyRotationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  test "the settings page offers the rotation, and the regeneration for emergencies" do
    sign_in users(:one)
    get settings_path

    assert_select "#ssh-key-actions form[action=?][data-turbo-confirm] button", settings_key_rotations_path, text: "Faire tourner la clé"
    assert_select "#ssh-key-actions form[action=?][data-confirm-variant=danger]", ssh_key_path
  end

  test "an admin starts a rotation" do
    sign_in users(:one)

    post settings_key_rotations_path

    rotation = KeyRotation.sole
    assert_enqueued_with(job: RotateSshKeyJob, args: [ rotation ])
    assert_redirected_to settings_key_rotation_path(rotation)
    assert_equal "Rotation de la clé Elio lancée sur 3 serveurs", Activity.of_kind(:ssh_key_rotation_started).sole.summary

    get settings_path
    assert_select "#key-rotation a[href=?]", settings_key_rotation_path(rotation), text: "Suivre la rotation"
  end

  test "a second rotation is refused while one is in progress" do
    KeyRotation.start!(by: users(:one))
    sign_in users(:one)

    post settings_key_rotations_path

    assert_redirected_to settings_path
    assert_equal "Une rotation de la clé est déjà en cours.", flash[:alert]
    assert_equal 1, KeyRotation.count
  end

  test "the page refreshes itself while running" do
    rotation = KeyRotation.start!(by: users(:one))
    sign_in users(:one)

    get settings_key_rotation_path(rotation)

    assert_select "[data-controller=auto-refresh]"
    assert_select ".rotation-status", text: /En cours : 0\/3/
  end

  test "a partial rotation can be retried or finalized" do
    rotation = KeyRotation.start!(by: users(:one))
    rotation.steps.create!(server: servers(:db), server_name: "Database", status: :failed, phase: "verify", error_message: "refused")
    rotation.finish!
    sign_in users(:one)

    get settings_key_rotation_path(rotation)
    assert_select "[data-controller=auto-refresh]", 0
    assert_select "li.rotation-step.is-failed", text: /Database — échec : connexion avec la nouvelle clé/

    post retry_settings_key_rotation_path(rotation)
    assert_enqueued_with(job: RotateSshKeyJob, args: [ rotation, { retry_failed: true } ])
    assert rotation.reload.running?
  end

  test "finalizing activates the new key" do
    rotation = KeyRotation.start!(by: users(:one))
    rotation.steps.create!(server: servers(:db), server_name: "Database", status: :failed, phase: "install", error_message: "refused")
    rotation.finish!
    sign_in users(:one)

    post finalize_settings_key_rotation_path(rotation)

    assert_equal :activated, rotation.reload.status
    assert_equal rotation.new_key, SshKey.current
  end

  test "a finished rotation cannot be finalized or retried" do
    rotation = KeyRotation.start!(by: users(:one)).tap(&:finish!)
    sign_in users(:one)

    post finalize_settings_key_rotation_path(rotation)
    assert_equal "Cette rotation ne peut pas être finalisée.", flash[:alert]
    post retry_settings_key_rotation_path(rotation)
    assert_equal "Rien à relancer.", flash[:alert]
  end
end
