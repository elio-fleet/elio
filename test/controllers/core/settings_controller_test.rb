require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "requires authentication" do
    get settings_path
    assert_redirected_to new_user_session_path
  end

  test "shows the public key, its fingerprint and the install command" do
    sign_in users(:one)
    key = ssh_keys(:main)

    get settings_path

    assert_response :success
    assert_select "#ssh-key-fingerprint", key.fingerprint
    assert_select "textarea#ssh-public-key", key.public_key
    assert_select "textarea#ssh-install-command", text: /echo '#{Regexp.escape(key.public_key)}' >> ~\/.ssh\/authorized_keys/
    assert_select "[data-controller=clipboard] button[data-action='clipboard#copy']", 2
    assert_select "#ssh-key-actions form[action=?][data-turbo-confirm][data-confirm-variant=danger] button", ssh_key_path, text: "Régénérer la clé"
  end

  test "one Save for the language, the thresholds and the prompt instructions" do
    sign_in users(:one)
    get settings_path
    assert_select "form#general-settings[action=?][data-controller=dirty-form]", settings_path do
      assert_select "#language select[name='app_setting[default_locale]']"
      assert_select "#health-thresholds input[name='app_setting[health_disk_warn]']"
      assert_select "#prompt-instructions textarea[name='prompt_instructions[firewall]']"
      assert_select ".save-bar[hidden] button", "Enregistrer"
    end
    assert_select "form#general-settings input[type=submit], form#general-settings .btn-primary", 1

    Server.update_all(health_status: "ok")
    patch settings_path, params: { app_setting: { default_locale: "en", health_disk_warn: 70 }, prompt_instructions: { firewall: "SSH last." } }
    assert_redirected_to settings_path
    setting = AppSetting.current.reload
    assert_equal [ "en", 70, "SSH last." ], [ setting.default_locale, setting.health_disk_warn, setting.prompt_instructions["firewall"] ]

    patch settings_path, params: { app_setting: { health_disk_warn: 0 } }
    assert_redirected_to settings_path
    assert_predicate flash[:alert], :present?
  end

  test "never renders the private key" do
    sign_in users(:one)

    get settings_path

    assert_no_match "PRIVATE KEY", response.body
    assert_no_match ssh_keys(:main).private_key.lines[1].strip, response.body
  end

  test "offers to generate a key when there is none" do
    SshKey.delete_all
    sign_in users(:one)

    get settings_path

    assert_select "#ssh-public-key", 0
    assert_select "form[action=?] button", ssh_key_path, text: "Générer une clé SSH"
  end

  test "is linked from the navbar" do
    sign_in users(:one)
    get root_path
    assert_select "nav a[href=?][title=Paramètres] svg", settings_path
  end
end
