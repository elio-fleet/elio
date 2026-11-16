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
    assert_select "nav.key-kind-filter a[aria-current=true]", "Toutes"
    assert_select "##{ActionView::RecordIdentifier.dom_id(public_keys(:ci))}" do
      assert_select "td.key-kind", "Serveur"
      assert_select ".key-description", "Runner GitHub Actions"
    end

    get public_keys_path(kind: "server")
    assert_select "nav.key-kind-filter a[aria-current=true][href=?]", public_keys_path(kind: "server"), text: "Serveurs"
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
    assert_select "nav.key-kind-filter a[data-kind=outside][aria-current=true]"
    assert_select "li.outside-key", 2
    assert_select "li.outside-key:first-child" do
      assert_select ".key-name", "bob@laptop"
      assert_select ".key-places a", 3
      assert_select ".key-places a[href=?]", server_path(servers(:web), tab: "keys"), text: "Web (root)"
      assert_select ".key-root", text: "root"
      assert_select "form[action=?] button.add-to-keyring", public_keys_path
      assert_select "form[action=?] input[name='public_key[name]'][value=?]", public_keys_path, "bob"
      assert_select "form[action=?] input[name=return_to][value=?]", public_keys_path, public_keys_path(kind: "outside")
      assert_select "details.tolerate-key form[action=?] input[name='tolerated_key[reason]'][required]", tolerated_keys_path
    end
    assert_select "li.outside-key:last-child" do
      assert_select ".key-name", "Sans nom"
      assert_select ".key-root", 0
      assert_select "a.add-to-keyring[href*='return_to=%2Fssh-keys%3Fkind%3Doutside']"
    end
    assert_select "#tolerated-keys", 0

    sign_in users(:viewer)
    get public_keys_path(kind: "outside")
    assert_select ".add-to-keyring", 0
    assert_select "details.tolerate-key", 0
  end

  test "outside the keyring: added in one click under the name of its comment" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@laptop").public_key
    AccountSnapshot.create!(server: servers(:web), unix_user: "deploy", content: bob, read_at: Time.current)
    sign_in users(:operator)

    post public_keys_path, params: { public_key: { name: "bob", content: bob, kind: "person" }, return_to: public_keys_path(kind: "outside") }

    assert_redirected_to public_keys_path(kind: "outside")
    assert_equal "bob", PublicKey.find_by!(fingerprint: AuthorizedKey.parse(bob).sole.fingerprint).name
    follow_redirect!
    assert_select "li.outside-key", 0
  end

  test "outside the keyring: when a key was first reported, and the tolerated keys" do
    bob = Ssh::KeyGenerator.generate(comment: "bob@laptop").public_key
    vendor = Ssh::KeyGenerator.generate(comment: "support@vendor")
    travel_to(3.days.ago) { AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(bob)) }
    AccountSnapshot.record!(servers(:db), AuthorizedKeysAccount.login(servers(:db)), AuthorizedKey.parse(vendor.public_key))
    ToleratedKey.create!(fingerprint: vendor.fingerprint, name: "support@vendor", reason: "Vendor support contract", user: users(:operator))
    sign_in users(:operator)

    get public_keys_path(kind: "outside")

    assert_select "li.outside-key", 1
    assert_select "li.outside-key .key-first-seen", /Signalée il y a 3 jours/
    assert_select "#tolerated-keys li.tolerated-key" do
      assert_select ".key-name", "support@vendor"
      assert_select ".key-reason", "Vendor support contract"
      assert_select "p", /Tolérée par operator@example.com/
      assert_select ".key-places a[href=?]", server_path(servers(:db), tab: "keys")
      assert_select "form[action=?] button.untolerate", tolerated_key_path(ToleratedKey.sole)
    end
  end

  test "the last keys scan summed up: never, by hand with a failure, planned and running" do
    sign_in users(:viewer)
    get public_keys_path
    assert_select "#keys-scan-summary [data-status=last_scan]", text: /Dernier scan\s*jamais/
    assert_select "#keys-scan-summary [data-status=outside]", 0, "nothing read yet"

    AccountSnapshot.create!(server: servers(:web), unix_user: "deploy", content: Ssh::KeyGenerator.generate(comment: "bob@laptop").public_key, read_at: 2.hours.ago)
    get public_keys_path
    assert_select "#keys-scan-summary [data-status=last_scan]", text: /il y a 2 heures/
    assert_select "#keys-scan-summary [data-status=outside]", text: /Hors trousseau\s*1 clé/

    task = BackgroundTask.enqueue!(kind: "keys_scan", label: "Scan", servers: [ servers(:web), servers(:db) ], user: users(:one))
    task.items.first.finish!(:succeeded)
    task.items.last.finish!(:failed, "refusé")
    get public_keys_path
    assert_select "#keys-scan-summary [data-status=last_scan]", text: %r{1/2 serveurs lus · 1 en échec}
    assert_select "#keys-scan-summary a[href=?]", task_path(task), text: "Voir la tâche"

    automation = Automation.find_or_create_by!(kind: "keys_scan") { |record| record.interval_minutes = 360 }
    planned = BackgroundTask.enqueue!(kind: "automation", label: "Scan planifié", servers: [ servers(:web) ], user: nil, automation: automation)
    get public_keys_path
    assert_select "#keys-scan-summary [data-status=last_scan]", text: %r{en cours \(0/1\)}
    assert_select "#keys-scan-summary a[href=?]", task_path(planned)

    planned.items.sole.finish!(:succeeded)
    BackgroundTask.enqueue!(kind: "inventory", label: "Inventaire", servers: [ servers(:web) ], user: nil)
    get public_keys_path
    assert_select "#keys-scan-summary [data-status=last_scan]", text: %r{1/1 serveur lu}
    assert_equal task_path(planned), css_select("#keys-scan-summary a").sole["href"], "an inventory is not a keys scan"
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
