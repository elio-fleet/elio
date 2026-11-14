require "test_helper"

class TwoFactorAuthenticatableTest < ActiveSupport::TestCase
  include TwoFactorHelpers

  setup do
    @user = users(:operator)
    @secret = User.generate_otp_secret
  end

  test "enables 2FA with a code that confirms the secret and returns 10 backup codes" do
    codes = @user.enable_two_factor!(@secret, ROTP::TOTP.new(@secret).now)

    assert @user.two_factor_enabled?
    assert_equal 10, codes.size
    assert codes.all? { |code| code.match?(/\A\h{5}-\h{5}\z/) }
    assert_equal 10, @user.backup_codes_left
    assert_not_includes @user.otp_backup_codes, codes.first
  end

  test "refuses a wrong confirmation code" do
    assert_nil @user.enable_two_factor!(@secret, "000000")
    assert_not @user.reload.two_factor_enabled?
  end

  test "the secret is encrypted at rest" do
    enable_two_factor(@user)
    raw = User.connection.select_value("SELECT otp_secret FROM users WHERE id = #{@user.id}")
    assert_not_includes raw, @user.otp_secret
  end

  test "accepts a valid code once, with spaces, and within the drift" do
    enable_two_factor(@user)
    code = next_totp(@user)

    assert_equal :totp, @user.verify_two_factor(code.dup.insert(3, " "))
    assert_nil @user.verify_two_factor(code), "a code must not be accepted twice"
    assert_nil @user.verify_two_factor(next_totp(@user, offset: 90.seconds)), "too far ahead of the clock"
  end

  test "refuses wrong, expired and blank codes, and everything when 2FA is off" do
    enable_two_factor(@user)

    assert_nil @user.verify_two_factor("123456")
    assert_nil @user.verify_two_factor(ROTP::TOTP.new(@user.otp_secret).at(5.minutes.ago))
    assert_nil @user.verify_two_factor("")
    assert_nil users(:viewer).verify_two_factor("123456")
  end

  test "a backup code works once, whatever its case or dashes" do
    codes = enable_two_factor(@user)

    assert_equal :backup_code, @user.verify_two_factor(codes.first.upcase.delete("-"))
    assert_equal 9, @user.reload.backup_codes_left
    assert_nil @user.verify_two_factor(codes.first)
    assert_nil @user.verify_two_factor("aaaaa-bbbbb")
  end

  test "regenerating backup codes invalidates the previous ones" do
    old_codes = enable_two_factor(@user)

    new_codes = @user.regenerate_backup_codes!

    assert_nil @user.verify_two_factor(old_codes.first)
    assert_equal :backup_code, @user.verify_two_factor(new_codes.first)
  end

  test "disabling clears everything" do
    enable_two_factor(@user)
    @user.disable_two_factor!

    assert_not @user.two_factor_enabled?
    assert_nil @user.otp_secret
    assert_equal 0, @user.backup_codes_left
  end

  test "2FA is required for admins without it when the setting is on" do
    AppSetting.current.update!(require_admin_two_factor: true)

    assert users(:one).two_factor_required?
    assert_not users(:operator).two_factor_required?
    enable_two_factor(users(:one))
    assert_not users(:one).two_factor_required?

    AppSetting.current.update!(require_admin_two_factor: false)
    assert_not users(:one).reload.tap(&:disable_two_factor!).two_factor_required?
  end

  test "with 2FA, a right password alone does not reset the failed attempts (the second step does)" do
    enable_two_factor(@user)
    @user.update_column(:failed_attempts, 4)
    @user.reset_failed_attempts!
    assert_equal 4, @user.reload.failed_attempts
    assert_equal 6, @user.attempts_left

    users(:viewer).update_column(:failed_attempts, 4)
    users(:viewer).reset_failed_attempts!
    assert_equal 0, users(:viewer).reload.failed_attempts
  end
end
