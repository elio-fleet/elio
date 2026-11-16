require "test_helper"

# Rate limits and first setup token of the public pages (AUDIT.md S2, S4).
class PublicPagesSecurityTest < ActionDispatch::IntegrationTest
  setup { Throttled::STORE.clear }
  teardown { Throttled::STORE.clear }

  test "sign in: 20 attempts per IP within 5 minutes (above the per-account lock)" do
    20.times { |index| post user_session_path, params: { user: { email: "nobody#{index}@example.com", password: "wrong-password" } } }
    assert_response :unprocessable_entity

    post user_session_path, params: { user: { email: users(:one).email, password: "password1234" } }
    assert_redirected_to new_user_session_path
    assert_equal "Trop de tentatives : réessayez dans quelques minutes.", flash[:alert]

    travel 6.minutes do
      post user_session_path, params: { user: { email: users(:one).email, password: "password1234" } }
      assert_redirected_to root_path
    end
  end

  test "password reset: 5 requests per IP within 10 minutes" do
    5.times { |index| post user_password_path, params: { user: { email: "x#{index}@example.com" } } }
    assert_redirected_to new_user_session_path

    post user_password_path, params: { user: { email: "y@example.com" } }
    assert_redirected_to new_user_password_path
    assert_match "Trop de tentatives", flash[:alert]
  end

  test "password reset: 5 requests per email within 10 minutes, whatever the IP" do
    5.times { |index| post user_password_path, params: { user: { email: "one@example.com" } }, env: { "REMOTE_ADDR" => "203.0.113.#{index + 1}" } }
    assert_redirected_to new_user_session_path

    post user_password_path, params: { user: { email: " ONE@example.com " } }, env: { "REMOTE_ADDR" => "203.0.113.50" }
    assert_redirected_to new_user_password_path
    assert_match "Trop de tentatives", flash[:alert]

    post user_password_path, params: { user: { email: "other@example.com" } }, env: { "REMOTE_ADDR" => "203.0.113.51" }
    assert_redirected_to new_user_session_path
  end

  test "invitation: 10 attempts per IP within 3 minutes" do
    10.times { post "/invitations/unknown-token", params: { user: { password: "x" } } }
    post "/invitations/unknown-token", params: { user: { password: "x" } }
    assert_redirected_to new_user_session_path
    assert_match "Trop de tentatives", flash[:alert]
  end

  test "first setup: the token is required when ELIO_SETUP_TOKEN is set" do
    User.delete_all
    params = { user: { email: "admin@example.com", password: "a-long-password", password_confirmation: "a-long-password" } }

    with_env("ELIO_SETUP_TOKEN" => "s3cret-token") do
      get new_setup_path
      assert_select "input[type=password][name=setup_token][required]"

      post setup_path, params: params.merge(setup_token: "wrong")
      assert_response :unprocessable_entity
      assert_select "#error_explanation", text: /Jeton de premier lancement incorrect/
      assert_not User.exists?

      post setup_path, params: params.merge(setup_token: "s3cret-token")
      assert_redirected_to root_path
      assert User.sole.admin?
    end
  end

  test "first setup without ELIO_SETUP_TOKEN: no token asked" do
    User.delete_all
    get new_setup_path
    assert_select "input[name=setup_token]", 0
  end

  private

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
