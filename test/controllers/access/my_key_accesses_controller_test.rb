require "test_helper"

class MyKeyAccessesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  def added = Keys::PublicKeyAuthorization::Result.new(status: :added, error_title: nil, error_details: nil)

  setup { public_keys(:alice).update!(user: users(:operator)) }

  test "adds my key for an hour by default on Elio's account, or for the duration and account chosen" do
    sign_in users(:operator)
    calls = []
    stub_method(Keys::AccessGrant, :call, ->(server, key, account:, duration:, **) { calls << [ server, key, account.unix_user, duration ]; added }) do
      post server_my_key_accesses_path(servers(:web))
      assert_redirected_to server_path(servers(:web))
      assert_match "« Alice » ajoutée sur le compte deploy pendant 1 heure", flash[:notice]

      post server_my_key_accesses_path(servers(:web)), params: { duration: "240", account: "root", public_key_id: public_keys(:alice).id }
    end
    assert_equal [ [ servers(:web), public_keys(:alice), "deploy", 1.hour ], [ servers(:web), public_keys(:alice), "root", 4.hours ] ], calls
  end

  test "without a key of mine, sends me to My SSH keys; never someone else's key" do
    public_keys(:alice).update!(user: users(:one))
    sign_in users(:operator)
    stub_method(Keys::AccessGrant, :call, ->(*) { flunk "no grant" }) do
      post server_my_key_accesses_path(servers(:web)), params: { public_key_id: public_keys(:alice).id }
    end
    assert_redirected_to account_path(anchor: "my-keys")
  end

  test "a viewer cannot add their key" do
    public_keys(:alice).update!(user: users(:viewer))
    sign_in users(:viewer)
    stub_method(Keys::AccessGrant, :call, ->(*) { flunk "no grant" }) do
      post server_my_key_accesses_path(servers(:web))
    end
    assert_response :forbidden

    get server_path(servers(:web))
    assert_select ".my-key-button", 0
  end

  test "the header shows the button, then until when my key is there; removing it revokes it" do
    sign_in users(:operator)
    get server_path(servers(:web))
    assert_select ".my-key-button", text: /Ajouter ma clé/

    access = TemporaryAccess.create!(server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy", key_blob: public_keys(:alice).authorized_key.key,
                                     fingerprint: public_keys(:alice).fingerprint, expires_at: Time.zone.parse("#{Date.current} 23:58"))
    get server_path(servers(:web))
    assert_select ".my-key-active", text: /Ma clé jusqu'à 23:58/
    assert_select "dialog .my-key-remove"

    revoked = []
    stub_method(Keys::Revocation, :call, ->(server, blob, account:, **) { revoked << [ server, blob, account.unix_user ]; Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil) }) do
      delete server_my_key_access_path(servers(:web), access)
    end
    assert_equal [ [ servers(:web), access.key_blob, "deploy" ] ], revoked
    assert_not access.reload.active?
    assert_match "retirée du compte deploy", flash[:notice]
  end

  test "someone else's access cannot be removed from my button" do
    other = TemporaryAccess.create!(server: servers(:web), public_key: public_keys(:alice), unix_user: "deploy", key_blob: "x", fingerprint: "y", expires_at: 1.hour.from_now)
    public_keys(:alice).update!(user: users(:one))
    sign_in users(:operator)
    delete server_my_key_access_path(servers(:web), other)
    assert_response :not_found
  end

  test "a user without a key gets a link to My SSH keys" do
    public_keys(:alice).update!(user: nil)
    sign_in users(:operator)
    get server_path(servers(:web))
    assert_select "a.my-key-button[href=?]", account_path(anchor: "my-keys")
  end
end
