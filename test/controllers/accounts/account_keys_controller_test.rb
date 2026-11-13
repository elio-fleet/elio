require "test_helper"

class AccountKeysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "a user claims a person's key nobody owns, then releases it; it is logged" do
    sign_in users(:operator)

    post account_keys_path, params: { public_key_id: public_keys(:alice).id }
    assert_redirected_to account_path(anchor: "my-keys")
    assert_equal users(:operator), public_keys(:alice).reload.user
    assert_equal "operator@example.com", Activity.of_kind(:public_key_owner_changed).last.data["owner"]

    get account_path
    assert_select "#my-keys li.my-key", text: /Alice/

    delete account_key_path(public_keys(:alice))
    assert_nil public_keys(:alice).reload.user
    assert_equal "Clé « Alice » attribuée à personne", Activity.recent.first.summary
  end

  test "a key owned by someone else cannot be claimed nor released" do
    public_keys(:alice).update!(user: users(:one))
    sign_in users(:operator)

    post account_keys_path, params: { public_key_id: public_keys(:alice).id }
    assert_response :not_found
    sign_in users(:operator)
    delete account_key_path(public_keys(:alice))
    assert_response :not_found
    assert_equal users(:one), public_keys(:alice).reload.user
  end

  test "a viewer sees the section but cannot claim" do
    sign_in users(:viewer)
    get account_path
    assert_select "#my-keys .my-keys-empty"
    assert_select "#my-keys form", 0

    post account_keys_path, params: { public_key_id: public_keys(:alice).id }
    assert_nil public_keys(:alice).reload.user
  end

  test "an administrator chooses the owner on the key's form, an operator cannot" do
    sign_in users(:operator)
    patch public_key_path(public_keys(:alice)), params: { public_key: { name: "Alice", user_id: users(:operator).id } }
    assert_nil public_keys(:alice).reload.user

    sign_in users(:one)
    get edit_public_key_path(public_keys(:alice))
    assert_select ".public-key-owner select[name='public_key[user_id]']"
    patch public_key_path(public_keys(:alice)), params: { public_key: { name: "Alice", user_id: users(:operator).id } }
    assert_equal users(:operator), public_keys(:alice).reload.user

    get public_key_path(public_keys(:alice))
    assert_select ".key-owner", "Clé de operator@example.com"
  end

  test "only a person's key has an owner" do
    key = PublicKey.new(name: "CI", kind: "server", content: Ssh::KeyGenerator.generate(comment: "ci").public_key.strip, user: users(:one))
    assert_not key.valid?
    assert_includes key.errors.full_messages.join, "seule la clé d'une personne"
  end
end
