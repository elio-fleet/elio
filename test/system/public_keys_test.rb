require "application_system_test_case"

class PublicKeysTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  setup do
    sign_in users(:one)
  end

  test "creating, editing and deleting a public_key" do
    key = Ssh::KeyGenerator.generate(comment: "bob@desktop")
    visit root_path

    within("nav.main-nav") { click_on "Clés SSH" }
    click_on "Ajouter une clé"
    fill_in "Nom", with: "Bob"
    fill_in "Clé SSH publique", with: key.public_key
    click_on "Ajouter au trousseau"

    assert_text "La clé « Bob » a été ajoutée au trousseau."
    assert_selector "#keyring-fingerprint", text: key.fingerprint

    click_on "Modifier"
    fill_in "Nom", with: "Bob Martin"
    click_on "Enregistrer"
    assert_text "La clé « Bob Martin » a été modifiée."

    dismiss_toasts
    find(".page-actions details.actions-menu summary").click
    accept_app_confirm { click_on "Supprimer" }
    assert_text "La clé « Bob Martin » a été retirée du trousseau."
    assert_no_selector "#keyring", text: "Bob Martin"
  end

  test "deleting from the public_keys page can be cancelled" do
    visit public_keys_path

    within("##{dom_id(public_keys(:alice))}") do
      dismiss_app_confirm { click_on "Supprimer" }
    end
    assert_selector "#keyring", text: "Alice"

    within("##{dom_id(public_keys(:alice))}") do
      accept_app_confirm { click_on "Supprimer" }
    end
    assert_text "La clé « Alice » a été retirée du trousseau."
  end

  test "invalid key shows the errors" do
    visit new_public_key_path
    fill_in "Nom", with: "Broken"
    fill_in "Clé SSH publique", with: "not a key"
    click_on "Ajouter au trousseau"

    assert_selector "#error_explanation", text: "doit être une seule clé publique"
  end

  test "outside the keyring: one key added in one click, another tolerated with a reason then no longer" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    vendor = Ssh::KeyGenerator.generate(comment: "support@vendor").public_key
    AccountSnapshot.create!(server: servers(:web), unix_user: "deploy", content: [ bob, vendor ].join("\n"), read_at: Time.current)
    visit public_keys_path(kind: "outside")

    within("li.outside-key", text: "bob@desktop") { click_on "Ajouter au trousseau" }
    assert_text "La clé « bob » a été ajoutée au trousseau."
    assert_selector "li.outside-key", count: 1

    within("li.outside-key", text: "support@vendor") do
      find("summary", text: "Tolérer…").click
      fill_in "tolerated_key[reason]", with: "Contrat de support"
      click_on "Tolérer"
    end
    assert_text "La clé « support@vendor » est tolérée"
    assert_no_selector "li.outside-key"
    assert_selector "#tolerated-keys .key-reason", text: "Contrat de support"

    within("#tolerated-keys") { click_on "Ne plus tolérer" }
    assert_text "La clé « support@vendor » n'est plus tolérée."
    assert_selector "li.outside-key", text: "support@vendor"
  end
end
