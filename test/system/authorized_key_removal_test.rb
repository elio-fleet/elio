require "application_system_test_case"

class AuthorizedKeyRemovalSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers

  setup do
    sign_in users(:one)
  end

  # Simulates the server's authorized_keys file in memory.
  test "deleting a key asks for confirmation and updates the list in place" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    lines = [ ssh_keys(:main).public_key, bob ]
    reader = lambda do |_server, account:, **|
      keys = AuthorizedKey.parse(lines.join("\n"))
      Keys::AuthorizedKeysReader::Result.new(keys: keys, error_title: nil, error_details: nil)
    end
    remover = lambda do |_server, blob, **|
      lines.reject! { |line| line.split(" ")[1] == blob }
      Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil)
    end

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(reader)) do
      stub_method(Keys::AuthorizedKeyRemoval, :call, remover) do
        visit server_path(servers(:web), tab: "keys")

        within("#server-authorized-keys") do
          assert_selector "li.authorized-key", count: 2
          assert_selector "li.authorized-key:first-child button[title='Supprimer la clé']", count: 0

          dismiss_app_confirm { find("li.authorized-key", text: "bob@desktop").click_on("Supprimer la clé") }
          assert_selector "li.authorized-key", count: 2

          accept_app_confirm { find("li.authorized-key", text: "bob@desktop").click_on("Supprimer la clé") }
          assert_selector "li.authorized-key", count: 1
          assert_selector ".key-master", text: "Master"
        end
        assert_selector "#flash", text: "La clé « bob@desktop » a été supprimée de « Web »."
      end
    end
  end
end
