require "application_system_test_case"

class ServerAuthorizationsTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup do
    sign_in users(:one)
  end

  # Simulates the authorized_keys file in memory: the reader lists it and the
  # authorization appends to it.
  test "authorizing a public_key" do
    lines = [ ssh_keys(:main).public_key ]
    reader = ->(*, **) { Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(lines.join("\n")), error_title: nil, error_details: nil) }
    authorizer = lambda do |_server, public_key, **|
      lines << "#{public_key.authorized_key.type} #{public_key.authorized_key.key} #{public_key.name}"
      Keys::PublicKeyAuthorization::Result.new(status: :added, error_title: nil, error_details: nil)
    end

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(reader)) do
      stub_method(Keys::PublicKeyAuthorization, :call, authorizer) do
        visit server_path(servers(:web), tab: "keys")

        assert_selector "li.authorized-key", count: 1
        open_add_key_dialog
        within("dialog.add-key-dialog[open]") do
          select "CI", from: "Clé du trousseau"
          click_on "Ajouter sur le serveur"
        end
        assert_no_selector "dialog.add-key-dialog[open]"
        within("#server-authorized-keys") do
          assert_selector ".key-keyring", text: "CI"
          assert_selector "li.authorized-key", count: 2
        end
        assert_selector "#flash", text: "La clé « CI » a été ajoutée sur « Web »."
      end
    end
  end

  test "authorizing a public_key for a limited time shows when it expires" do
    lines = [ ssh_keys(:main).public_key ]
    reader = ->(*, **) { Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(lines.join("\n")), error_title: nil, error_details: nil) }
    authorizer = lambda do |_server, public_key, expires_at:, **|
      lines << Keys::PublicKeyAuthorization.line_for(public_key, expires_at)
      Keys::PublicKeyAuthorization::Result.new(status: :added, error_title: nil, error_details: nil)
    end

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(reader)) do
      stub_method(Keys::PublicKeyAuthorization, :call, authorizer) do
        visit server_path(servers(:web), tab: "keys")

        open_add_key_dialog
        within("dialog.add-key-dialog[open]") do
          select "CI", from: "Clé du trousseau"
          select "10 minutes", from: "Durée"
          click_on "Ajouter sur le serveur"
        end

        within("#server-authorized-keys") do
          within("li.authorized-key", text: "CI") do
            assert_selector ".key-expiry", text: "Expire dans 10 minutes"
            assert_selector "dialog.key-details .key-options", text: "expiry-time=", visible: :all
          end
        end
        assert_selector "#flash", text: "La clé « CI » est ajoutée sur « Web » pendant 10 minutes"
        assert_equal 1, TemporaryAccess.active.count
      end
    end
  end

  test "adding a new key: errors keep the dialog open, then it lands in the keyring and on the server" do
    lines = [ ssh_keys(:main).public_key ]
    reader = ->(*, **) { Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(lines.join("\n")), error_title: nil, error_details: nil) }
    authorizer = lambda do |_server, public_key, **|
      lines << "#{public_key.authorized_key.type} #{public_key.authorized_key.key} #{public_key.name}"
      Keys::PublicKeyAuthorization::Result.new(status: :added, error_title: nil, error_details: nil)
    end
    bob = Ssh::KeyGenerator.generate(comment: "bob@laptop").public_key

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(reader)) do
      stub_method(Keys::PublicKeyAuthorization, :call, authorizer) do
        visit server_path(servers(:web), tab: "keys")
        assert_selector "li.authorized-key", count: 1

        open_add_key_dialog
        within("dialog.add-key-dialog[open]") do
          choose "Nouvelle clé", allow_label_click: true
          assert_no_field "Clé du trousseau"
          fill_in "Nom", with: "Bob"
          fill_in "Clé SSH publique", with: "pas une clé"
          click_on "Ajouter sur le serveur"
        end

        within("dialog.add-key-dialog[open]") do
          assert_selector "#error_explanation"
          assert_field "Nom", with: "Bob"
          fill_in "Clé SSH publique", with: bob
          click_on "Ajouter sur le serveur"
        end

        assert_no_selector "dialog.add-key-dialog[open]"
        assert_selector "#flash", text: "La clé « Bob » (ajoutée au trousseau) a été ajoutée sur « Web »."
        within("#server-authorized-keys") { assert_selector ".key-keyring", text: "Bob" }
        assert PublicKey.exists?(name: "Bob")
      end
    end
  end

  private

  # The button only works once Stimulus has connected the dialog: click again
  # until it opens (a click right after the visit can come too early).
  def open_add_key_dialog
    3.times do
      click_on "Ajouter une clé"
      return if has_selector?("dialog.add-key-dialog[open]", wait: 1)
    end
    assert_selector "dialog.add-key-dialog[open]"
  end
end
