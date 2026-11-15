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

  test "a password changed: when, and what to do if it was not them" do
    mail = AccountMailer.password_changed(users(:operator), at: Time.zone.local(2026, 11, 14, 9, 30))

    assert_equal [ "operator@example.com" ], mail.to
    assert_equal "Votre mot de passe Elio a été changé", mail.subject
    body = mail.body.to_s
    assert_match "votre compte Elio operator@example.com a été changé le samedi 14 novembre 2026 09h30", body
    assert_match "prévenez tout de suite un administrateur", body
    assert_match "http://example.com/account", body
  end
end
