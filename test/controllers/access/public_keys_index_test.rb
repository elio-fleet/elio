require "test_helper"

class PublicKeysIndexTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "requires authentication" do
    get public_keys_path
    assert_redirected_to new_user_session_path
  end

  test "lists public_keys sorted by name with their actions" do
    sign_in users(:one)
    get public_keys_path

    assert_select "#keyring-section a[href=?]", new_public_key_path, text: "Ajouter une clé"
    assert_select "#keyring tbody tr", 2
    assert_select "#keyring tbody tr:first-child td:first-child a:first-child", "Alice"
    PublicKey.find_each do |public_key|
      assert_select "##{ActionView::RecordIdentifier.dom_id(public_key)}" do
        assert_select "td a[href=?]", public_key_path(public_key), text: public_key.name
        assert_select "td", text: "ssh-ed25519"
        assert_select "td", text: public_key.fingerprint
        assert_select "a[href=?][title=Modifier]", edit_public_key_path(public_key)
        assert_select "form[action=?][data-turbo-confirm] button[title=Supprimer]", public_key_path(public_key)
      end
    end
  end

  test "shows an empty state when there are no public_keys" do
    PublicKey.delete_all
    sign_in users(:one)
    get public_keys_path

    assert_select "#keyring", 0
    assert_select "#keyring-section p", text: "Le trousseau est vide."
  end

  test "shows each key's kind and description, and filters by kind" do
    sign_in users(:one)

    get public_keys_path
    assert_select "nav.key-kind-filter a[aria-current=page]", "Toutes"
    assert_select "##{ActionView::RecordIdentifier.dom_id(public_keys(:ci))}" do
      assert_select "td.key-kind", "Serveur"
      assert_select ".key-description", "Runner GitHub Actions"
    end

    get public_keys_path(kind: "server")
    assert_select "nav.key-kind-filter a[aria-current=page][href=?]", public_keys_path(kind: "server"), text: "Serveurs"
    assert_select "#keyring tbody tr", 1
    assert_select "#keyring tbody tr td a", text: "CI"

    get public_keys_path(kind: "nope")
    assert_select "#keyring tbody tr", 2
  end

  test "outside the keyring: the keys of the servers in no keyring key, grouped, with where they are" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@laptop").public_key
    unnamed = Ssh::KeyGenerator.generate(comment: "").public_key.strip
    AccountSnapshot.create!(server: servers(:web), unix_user: "deploy", content: [ ssh_keys(:main).public_key, bob, public_keys(:alice).content ].join("\n"), read_at: Time.current)
    AccountSnapshot.create!(server: servers(:web), unix_user: "root", content: bob, read_at: Time.current)
    AccountSnapshot.create!(server: servers(:db), unix_user: "admin", content: [ bob, unnamed ].join("\n"), read_at: Time.current)
    sign_in users(:operator)

    get public_keys_path
    assert_select "nav.key-kind-filter a[data-kind=outside][href=?]", public_keys_path(kind: "outside"), text: /Hors trousseau\s*2/

    get public_keys_path(kind: "outside")
    assert_response :success
    assert_select "nav.key-kind-filter a[data-kind=outside][aria-current=page]"
    assert_select "li.outside-key", 2
    assert_select "li.outside-key:first-child" do
      assert_select ".key-name", "bob@laptop"
      assert_select ".key-places a", 3
      assert_select ".key-places a[href=?]", server_path(servers(:web), tab: "keys"), text: "Web (root)"
      assert_select "a.add-to-keyring[href*='return_to=%2Fkeys%3Fkind%3Doutside']"
    end
    assert_select "li.outside-key:last-child .key-name", "Sans nom"

    sign_in users(:viewer)
    get public_keys_path(kind: "outside")
    assert_select "a.add-to-keyring", 0
  end

  test "outside the keyring, empty or never scanned" do
    sign_in users(:viewer)
    get public_keys_path(kind: "outside")
    assert_select ".outside-none", /scannez les clés/

    AccountSnapshot.create!(server: servers(:web), unix_user: "deploy", content: public_keys(:alice).content, read_at: Time.current)
    get public_keys_path(kind: "outside")
    assert_select ".outside-none", /Toutes les clés/
  end
end
