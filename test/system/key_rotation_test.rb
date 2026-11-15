require "application_system_test_case"

class KeyRotationTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include ActiveJob::TestHelper

  test "rotating the Elio key without downtime" do
    stub_method_until_teardown(Ssh::Connection, :open, ->(*, **, &block) { block.call(Object.new.tap { |ssh| def ssh.run_command!(*, **) = true }) })
    stub_method_until_teardown(Ssh::Check, :call, Ssh::Check::Result.new(success: true, message: "ok", details: "ok"))
    stub_method_until_teardown(Keys::AuthorizedKeyRemoval, :call, Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil))
    old_fingerprint = ssh_keys(:main).fingerprint
    sign_in users(:one)
    visit settings_path

    find("#ssh-key-actions summary").click
    accept_app_confirm("Lancer la rotation") { click_on "Faire tourner la clé" }

    assert_selector "h2", text: "Rotation de la clé Elio"
    assert_selector ".rotation-status", text: "En cours : 0/3 serveurs"
    perform_enqueued_jobs # the page refreshes itself and shows the result

    assert_selector ".rotation-status", text: "Terminée : la nouvelle clé est active, l'ancienne a été supprimée."
    assert_selector "li.rotation-step.is-rotated", count: 3

    visit settings_path
    assert_no_selector "#ssh-key-fingerprint", text: old_fingerprint
    assert_selector "#ssh-key-actions button", text: "Faire tourner la clé", visible: :all
  end

  test "a dry run tells which servers would fail, without changing anything" do
    results = { "Database" => Keys::RotationCheck::Result.new(status: :read_only, message: "Le fichier ~/.ssh/authorized_keys de admin est en lecture seule") }
    stub_method_until_teardown(Keys::RotationCheck, :call, ->(server, **) { results.fetch(server.name) { Keys::RotationCheck::Result.new(status: :ready, message: "Prêt") } })
    sign_in users(:one)
    visit settings_path

    find("#ssh-key-actions summary").click
    click_on "Simuler une rotation"
    assert_text "Simulation lancée"
    perform_enqueued_jobs
    visit current_path

    assert_text "Simulation de rotation de la clé (3 serveurs)"
    assert_text "Le fichier ~/.ssh/authorized_keys de admin est en lecture seule"
    assert_equal 0, KeyRotation.count
  end
end
