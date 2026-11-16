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

  test "the confirmation of a new email goes to the new address, with a link valid one day" do
    user = users(:operator)
    user.request_email_change("new@example.com", current_password: "password1234", confirm: true)

    mail = AccountMailer.email_change_confirmation(user)

    assert_equal [ "new@example.com" ], mail.to
    assert_equal "Confirmez votre nouvel email pour Elio", mail.subject
    body = mail.body.to_s
    assert_match "Le compte Elio operator@example.com a demandé à utiliser désormais cette adresse (new@example.com)", body
    assert_match "Le lien est valable 24 heures", body
    token = body[%r{/account/email/confirm\?token=(\S+)}, 1]
    assert_equal user, User.find_by_token_for(:email_change, CGI.unescape(token))
  end

  test "the current address is told about the change, in the language of the user" do
    user = users(:operator)
    user.update!(locale: "en")
    user.request_email_change("new@example.com", current_password: "password1234", confirm: true)

    mail = AccountMailer.email_change_requested(user)

    assert_equal [ "operator@example.com" ], mail.to
    assert_equal "Your Elio email is about to change", mail.subject
    assert_match "your Elio account operator@example.com to new@example.com was asked", mail.body.to_s
    assert_match "http://example.com/account", mail.body.to_s
  end
end
