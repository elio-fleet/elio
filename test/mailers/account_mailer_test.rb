require "test_helper"

class AccountMailerTest < ActionMailer::TestCase
  include TwoFactorHelpers

  test "a backup code used: when, from where, how many are left" do
    enable_two_factor(users(:operator))

    mail = AccountMailer.backup_code_used(users(:operator), ip: "203.0.113.7", at: Time.zone.local(2026, 11, 14, 9, 30))

    assert_equal [ "operator@example.com" ], mail.to
    assert_equal "Un code de secours a servi à vous connecter à Elio", mail.subject
    body = mail.body.to_s
    assert_match "votre compte Elio operator@example.com le samedi 14 novembre 2026 09h30 (adresse IP : 203.0.113.7)", body
    assert_match "Il vous reste 10 codes de secours.", body
    assert_match "http://example.com/account", body
  end

  test "in the language of the user, and says when no code is left" do
    users(:operator).update!(locale: "en", otp_backup_codes: [])

    mail = AccountMailer.backup_code_used(users(:operator), ip: "203.0.113.7", at: Time.current)

    assert_equal "A backup code was used to sign in to Elio", mail.subject
    assert_match "You have no backup code left", mail.body.to_s
  end

  test "a sign in from a new browser: when, from where, which browser" do
    mail = AccountMailer.new_device_sign_in(users(:operator), ip: "203.0.113.7", at: Time.zone.local(2026, 11, 14, 9, 30), browser: "Mozilla/5.0 (X11; Linux x86_64) Firefox/140.0")

    assert_equal [ "operator@example.com" ], mail.to
    assert_equal "Nouvelle connexion à Elio depuis un autre navigateur", mail.subject
    body = mail.body.to_s
    assert_match "votre compte Elio operator@example.com a eu lieu depuis un nouveau navigateur le samedi 14 novembre 2026 09h30 (adresse IP : 203.0.113.7)", body
    assert_match "Navigateur : Mozilla/5.0 (X11; Linux x86_64) Firefox/140.0", body
    assert_match "http://example.com/account", body
  end

  test "a sign in from a new browser, in English and without a user agent" do
    users(:operator).update!(locale: "en")

    mail = AccountMailer.new_device_sign_in(users(:operator), ip: "203.0.113.7", at: Time.current, browser: "")

    assert_equal "New sign in to Elio from another browser", mail.subject
    assert_no_match "Browser:", mail.body.to_s
  end
end
