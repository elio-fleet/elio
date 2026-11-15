require "test_helper"

class SetupsControllerTest < ActionDispatch::IntegrationTest
  include StubHelpers

  def without_users
    Invitation.delete_all
    Activity.delete_all
    User.delete_all
  end

  test "every page leads to the setup page while there is no user" do
    without_users

    [ root_path, servers_path, new_user_session_path ].each do |path|
      get path
      assert_redirected_to new_setup_path
    end
  end

  test "creates the first admin and signs them in" do
    without_users

    get new_setup_path
    assert_select "h2", "Créer le compte administrateur"

    post setup_path, params: { user: { email: "admin@example.com", password: "password1234", password_confirmation: "password1234" } }

    assert_redirected_to root_path
    user = User.sole
    assert user.admin?
    follow_redirect!
    assert_response :success
    assert_select ".sidebar .user-role", "Admin"
  end

  test "the language the first admin sets Elio up in becomes the language of the installation" do
    without_users
    AppSetting.current.update!(default_locale: "en")

    post setup_path, params: { user: { email: "admin@example.com", password: "password1234", password_confirmation: "password1234" } },
                     headers: { "Accept-Language" => "fr-FR,fr;q=0.9" }

    assert_equal "fr", AppSetting.current.reload.default_locale
  end

  test "the language picked on the page comes before the browser's and is kept on an error" do
    without_users
    AppSetting.current.update!(default_locale: "fr")
    french_browser = { "Accept-Language" => "fr-FR,fr;q=0.9" }

    get new_setup_path(locale: "en"), headers: french_browser
    assert_select "h2", "Create the administrator account"
    assert_select ".setup-languages a[href=?]", new_setup_path(locale: "fr"), text: "Français"

    post setup_path, params: { locale: "en", user: { email: "nope", password: "a", password_confirmation: "a" } }, headers: french_browser
    assert_response :unprocessable_entity
    assert_select "h2", "Create the administrator account"
    assert_select "input[type=hidden][name=locale][value=en]"

    post setup_path, params: { locale: "en", user: { email: "admin@example.com", password: "password1234", password_confirmation: "password1234" } },
                     headers: french_browser
    assert_equal "en", AppSetting.current.reload.default_locale
    assert_equal "en", User.sole.locale
  end

  test "without a language picked, the first admin follows their browser" do
    without_users

    post setup_path, params: { user: { email: "admin@example.com", password: "password1234", password_confirmation: "password1234" } }

    assert_nil User.sole.locale
  end

  test "goes straight to the 2FA setup when it is mandatory for admins" do
    without_users
    AppSetting.current.update!(require_admin_two_factor: true)

    post setup_path, params: { user: { email: "admin@example.com", password: "password1234", password_confirmation: "password1234" } }

    assert_redirected_to new_two_factor_path
    assert_nil flash[:notice]
  end

  test "warns when ELIO_HOST is missing or is another address than the page's" do
    without_users

    with_env("ELIO_HOST" => nil) do
      get new_setup_path
      assert_select ".setup-address-warning", text: /La variable ELIO_HOST n'est pas définie.*www\.example\.com/
    end
    with_env("ELIO_HOST" => "elio.example.org") do
      get new_setup_path
      assert_select ".setup-address-warning", text: /ELIO_HOST vaut elio\.example\.org mais cette page est ouverte à l'adresse www\.example\.com/
    end
    with_env("ELIO_HOST" => "WWW.example.com") do
      get new_setup_path
      assert_select ".setup-address-warning", 0
    end
  end

  test "shows what would break the installation, from the doctor's checks" do
    without_users
    get new_setup_path
    assert_select ".setup-failures", 0

    failure = Installation::Doctor::Check.new(:failure, "Secrets", "SECRET_KEY_BASE missing.", "Set it.")
    warning = Installation::Doctor::Check.new(:warning, "Emails", "Not configured.", "Set SMTP_ADDRESS.")
    stub_method(Installation::Doctor, :new, ->(**) { Struct.new(:call).new([ failure, warning ]) }) do
      get new_setup_path
    end
    assert_select ".setup-failures li", 1
    assert_select ".setup-failures li", text: /Secrets — SECRET_KEY_BASE missing\.\s*Set it\./
  end

  test "re-renders the form with errors" do
    without_users

    post setup_path, params: { user: { email: "nope", password: "a", password_confirmation: "b" } }

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", minimum: 2
    assert_equal 0, User.count
  end

  test "is unavailable once a user exists" do
    get new_setup_path
    assert_response :not_found

    assert_no_difference "User.count" do
      post setup_path, params: { user: { email: "intruder@example.com", password: "password1234", password_confirmation: "password1234" } }
    end
    assert_response :not_found
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
