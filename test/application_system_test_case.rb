require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Chrome's password manager and leak detection pop up (invisibly in headless
  # mode) after a form with "password1234" is submitted and swallow the next
  # clicks: turn them off.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ] do |options|
    # The tests read the interface in French (see config/environments/test.rb).
    options.add_preference("intl.accept_languages", "fr-FR,fr")
    options.add_argument("--lang=fr-FR")
    options.add_preference("credentials_enable_service", false)
    options.add_preference("profile.password_manager_enabled", false)
    options.add_preference("profile.password_manager_leak_detection", false)
    options.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding,PasswordCheck")
    # Browser console, read by the tests (Content Security Policy violations).
    options.add_option("goog:loggingPrefs", { browser: "ALL" })
  end

  include TcpHelpers

  # Pages load several Turbo Frames in parallel: give elements a bit more time.
  Capybara.default_max_wait_time = 5

  # Server pages check the port and SSH access on display: point every server
  # at a closed local port so no test reaches the network (or waits for it).
  setup { Server.update_all(host: "127.0.0.1", port: closed_port) }

  # Let the frames still loading finish, so their requests cannot run into the
  # next test (and slow it down) once this one is over.
  teardown { page.has_no_selector?("turbo-frame[busy]", wait: 10) }

  # The fleet page's actions are in its "Actions" menu.
  def fleet_action(label)
    find("#fleet-actions summary").click
    within("#fleet-actions [role=menu]") { click_on label }
  end

  # The app replaces confirm() with its own dialog (app/javascript/confirm_dialog.js).
  # Looked up from the document root, whatever the current `within` scope.
  def accept_app_confirm(button = nil)
    yield
    dialog = page.document.find("#confirm-dialog[open]")
    button ? dialog.click_on(button) : dialog.find("[data-confirm-accept]").click
    page.document.assert_no_selector "#confirm-dialog[open]"
  end

  def dismiss_app_confirm
    yield
    page.document.find("#confirm-dialog[open]").click_on("Annuler")
    page.document.assert_no_selector "#confirm-dialog[open]"
  end
end
