require "test_helper"

class EmailChangeableTest < ActiveSupport::TestCase
  setup { @user = users(:viewer) }

  test "with confirmation, the new address waits and the email stays" do
    assert @user.request_email_change(" New@Example.com ", current_password: "password1234", confirm: true)

    @user.reload
    assert_equal "viewer@example.com", @user.email
    assert_equal "new@example.com", @user.unconfirmed_email
    assert @user.email_change_pending?
  end

  test "without confirmation, the email changes at once" do
    assert @user.request_email_change("new@example.com", current_password: "password1234", confirm: false)

    assert_equal "new@example.com", @user.reload.email
    assert_nil @user.unconfirmed_email
  end

  test "the current password is required" do
    assert_not @user.request_email_change("new@example.com", current_password: "wrong", confirm: true)
    assert @user.errors.of_kind?(:current_password, :invalid)
    assert_not @user.request_email_change("new@example.com", current_password: "", confirm: false)
    assert @user.errors.of_kind?(:current_password, :blank)
    assert_nil @user.reload.unconfirmed_email
    assert_equal "viewer@example.com", @user.email
  end

  test "refuses an invalid address, the current one or one of another user" do
    { "not-an-email" => :invalid, "viewer@example.com" => :unchanged, "operator@example.com" => :taken, "" => :blank }.each do |email, error|
      assert_not @user.request_email_change(email, current_password: "password1234", confirm: true), email
      assert @user.errors.of_kind?(:unconfirmed_email, error), "#{email}: #{@user.errors.details}"
    end
    assert_nil @user.reload.unconfirmed_email

    assert_not @user.request_email_change("operator@example.com", current_password: "password1234", confirm: false)
    assert @user.errors.of_kind?(:email, :taken)
  end

  test "the link works once, for the address it was sent to" do
    @user.request_email_change("new@example.com", current_password: "password1234", confirm: true)
    token = @user.generate_token_for(:email_change)
    assert_equal @user, User.find_by_token_for(:email_change, token)

    @user.request_email_change("other@example.com", current_password: "password1234", confirm: true)
    assert_nil User.find_by_token_for(:email_change, token), "another address asked since"

    token = @user.generate_token_for(:email_change)
    @user.confirm_email_change!
    assert_equal "other@example.com", @user.reload.email
    assert_nil @user.unconfirmed_email
    assert_nil User.find_by_token_for(:email_change, token), "already used"
  end

  test "the link expires" do
    @user.request_email_change("new@example.com", current_password: "password1234", confirm: true)
    token = @user.generate_token_for(:email_change)

    travel EmailChangeable::CONFIRMATION_VALIDITY + 1.minute do
      assert_nil User.find_by_token_for(:email_change, token)
    end
  end

  test "cancelling forgets the new address" do
    @user.request_email_change("new@example.com", current_password: "password1234", confirm: true)
    @user.cancel_email_change!

    assert_not @user.reload.email_change_pending?
  end
end
