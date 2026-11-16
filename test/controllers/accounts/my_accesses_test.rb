require "test_helper"

# My account: the temporary accesses of the user's keys in progress.
class MyAccessesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include TemporaryAccessHelpers

  test "My account lists the temporary accesses of my keys in progress" do
    public_keys(:alice).update!(user: users(:operator))
    create_temporary_access(public_key: public_keys(:alice), unix_user: "root", expires_at: 2.hours.from_now)
    create_temporary_access(public_key: public_keys(:ci), unix_user: "deploy") # not mine
    create_temporary_access(public_key: public_keys(:alice), server: servers(:db)).end! # ended

    sign_in users(:operator)
    get account_path

    assert_select "#my-accesses .my-access", 1 do
      assert_select "a[href=?]", server_temporary_accesses_path(servers(:web)), servers(:web).name
      assert_select ".font-mono", "root"
    end

    sign_in users(:viewer) # no key: no section
    get account_path
    assert_select "#my-accesses", 0
  end

  test "My account says when no temporary access of mine is in progress" do
    public_keys(:alice).update!(user: users(:operator))
    sign_in users(:operator)
    get account_path

    assert_select "#my-accesses .my-accesses-empty", "Aucun en cours."
  end
end
