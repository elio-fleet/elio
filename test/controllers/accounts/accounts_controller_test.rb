require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include TwoFactorHelpers

  test "requires authentication" do
    get account_path
    assert_redirected_to new_user_session_path
  end

  test "shows the account with its 2FA state, reachable from the navbar" do
    sign_in users(:viewer)
    get root_path
    assert_select ".sidebar a.account-link[href=?]", account_path

    get account_path
    assert_select "h1", "Mon compte"
    assert_select ".two-factor-state", "Désactivée"
    assert_select "a[href=?]", new_two_factor_path
  end

  test "changing the password keeps the session" do
    sign_in users(:viewer)

    patch password_account_path, params: { user: { current_password: "password1234", password: "new-password-1", password_confirmation: "new-password-1" } }

    assert_redirected_to account_path
    assert users(:viewer).reload.valid_password?("new-password-1")
    get root_path
    assert_response :success
  end

  test "changing the password requires the current one" do
    sign_in users(:viewer)

    patch password_account_path, params: { user: { current_password: "wrong", password: "new-password-1", password_confirmation: "new-password-1" } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation li"
    assert users(:viewer).reload.valid_password?("password1234")
  end

  test "enabling 2FA shows a QR code, then the backup codes once" do
    sign_in users(:viewer)

    get new_two_factor_path
    assert_select ".two-factor-qr img[src^='data:image/svg+xml;base64,'][alt]"
    # Black on white with a quiet zone, whatever the theme (readable in dark mode).
    svg = Base64.decode64(css_select(".two-factor-qr img").first["src"].delete_prefix("data:image/svg+xml;base64,"))
    assert_match(/fill="#fff"/, svg)
    assert_match(/fill="#000"/, svg)
    assert_select ".two-factor-qr.bg-white"
    assert_select "form[action=?][data-turbo=false]", two_factor_path
    secret = session[:pending_otp_secret]
    assert_select ".two-factor-secret", secret.scan(/.{4}/).join(" ")

    post two_factor_path, params: { code: ROTP::TOTP.new(secret).now }

    assert_response :success
    assert_select "textarea.backup-codes", text: /\h{5}-\h{5}/
    assert users(:viewer).reload.two_factor_enabled?
    assert_nil session[:pending_otp_secret]
    assert_equal "2FA activée pour viewer@example.com", Activity.of_kind(:two_factor_enabled).sole.summary
  end

  test "a wrong confirmation code does not enable 2FA" do
    sign_in users(:viewer)
    get new_two_factor_path

    post two_factor_path, params: { code: "000000" }

    assert_redirected_to new_two_factor_path
    assert_not users(:viewer).reload.two_factor_enabled?
  end

  test "disabling 2FA requires a valid code" do
    enable_two_factor(users(:viewer))
    sign_in users(:viewer)

    delete two_factor_path, params: { code: "000000" }
    assert users(:viewer).reload.two_factor_enabled?

    delete two_factor_path, params: { code: next_totp(users(:viewer)) }
    assert_not users(:viewer).reload.two_factor_enabled?
    assert_equal "2FA désactivée pour viewer@example.com", Activity.of_kind(:two_factor_disabled).sole.summary
  end

  test "an admin cannot disable 2FA while it is mandatory" do
    AppSetting.current.update!(require_admin_two_factor: true)
    enable_two_factor(users(:one))
    sign_in users(:one)

    delete two_factor_path, params: { code: next_totp(users(:one)) }

    assert users(:one).reload.two_factor_enabled?
    assert_match "obligatoire", flash[:alert]
  end

  test "regenerating backup codes requires a valid code" do
    old_codes = enable_two_factor(users(:viewer))
    sign_in users(:viewer)

    post backup_codes_two_factor_path, params: { code: next_totp(users(:viewer)) }

    assert_select "textarea.backup-codes"
    assert_nil users(:viewer).reload.verify_two_factor(old_codes.first)
  end

  test "an admin without 2FA is sent to their account while it is mandatory" do
    AppSetting.current.update!(require_admin_two_factor: true)
    sign_in users(:one)

    get servers_path
    assert_redirected_to account_path
    assert_match "obligatoire", flash[:alert]

    get account_path
    assert_response :success
    get new_two_factor_path
    assert_response :success
  end

  test "operators are not forced to enable 2FA" do
    AppSetting.current.update!(require_admin_two_factor: true)
    sign_in users(:operator)

    get servers_path
    assert_response :success
  end
end
