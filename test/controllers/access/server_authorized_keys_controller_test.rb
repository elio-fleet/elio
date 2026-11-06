require "test_helper"

class ServerAuthorizedKeysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier
  include StubHelpers
  include TcpHelpers
  include TemporaryAccessHelpers

  def frame_id = dom_id(servers(:web), :authorized_keys)

  def keys_result(*lines)
    Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(lines.join("\n")), error_title: nil, error_details: nil)
  end

  test "requires authentication" do
    get server_authorized_keys_path(servers(:web))
    assert_redirected_to new_user_session_path
  end

  test "returns 404 for an unknown server" do
    sign_in users(:one)
    get server_authorized_keys_path(server_id: 0)
    assert_response :not_found
  end

  test "lists keys with keyring, unknown and master badges" do
    sign_in users(:one)
    other = Ssh::KeyGenerator.generate
    unnamed = other.public_key.split(" ").first(2).join(" ")

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(ssh_keys(:main).public_key, unnamed, public_keys(:alice).content))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_response :success
    assert_select "turbo-frame##{frame_id}" do
      assert_select "p", text: /3 clés/
      assert_select "li.authorized-key", 3
      assert_select "li.authorized-key:nth-child(1)" do
        assert_select ".key-name", "elio-fixture"
        assert_select ".key-unknown", 0
        assert_select ".key-master", text: "Master"
      end
      assert_select "li.authorized-key:nth-child(2)" do
        assert_select ".key-name", "Sans nom"
        assert_select ".key-unknown", text: "Hors trousseau"
        assert_select ".key-master", 0
        assert_select "dialog.key-details .key-fingerprint", other.fingerprint
      end
      assert_select "li.authorized-key:nth-child(3)" do
        assert_select "a.key-name.key-keyring", "Alice"
        assert_select ".key-kind", "Personne"
        assert_select ".key-comment", "alice@laptop"
        assert_select ".key-unknown", 0
        assert_select ".key-master", 0
      end
      assert_select "a[href=?][title=?]", server_authorized_keys_path(servers(:web)), "Recharger les clés"
    end
  end

  test "flags the master key even if renamed on the server" do
    sign_in users(:one)
    renamed = ssh_keys(:main).public_key.split(" ").first(2).join(" ")

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(renamed))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select ".key-unknown", 0
    assert_select ".key-master", text: "Master"
  end

  test "shows options when a key has some" do
    sign_in users(:one)
    key = Ssh::KeyGenerator.generate(comment: "ci").public_key

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(%(from="10.0.0.1",no-pty #{key})))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select "dialog.key-details .key-options", %(from="10.0.0.1",no-pty)
  end

  test "shows an empty state when there are no keys" do
    sign_in users(:one)

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result)) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select "turbo-frame##{frame_id} p", text: "Aucune clé autorisée sur ce serveur."
  end

  test "shows the error when the keys cannot be read" do
    Server.update_all(host: "127.0.0.1", port: closed_port)
    sign_in users(:one)

    get server_authorized_keys_path(servers(:web))

    assert_select "turbo-frame##{frame_id} .authorized-keys-error", text: /Connexion impossible/
    assert_select "li.authorized-key", 0
  end

  test "the server page lazy-loads the frame" do
    sign_in users(:one)

    get server_path(servers(:web), tab: "keys")

    assert_select "#server-authorized-keys turbo-frame##{frame_id}[loading=lazy][src=?]", server_authorized_keys_path(servers(:web))
  end

  test "names the keys of the keyring, whatever their comment" do
    sign_in users(:one)
    type, blob = public_keys(:alice).content.split(" ")

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result("#{type} #{blob} renamed"))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select "li.authorized-key a.key-keyring[href=?][data-turbo-frame=_top]", public_key_path(public_keys(:alice)), text: "Alice"
    assert_select "li.authorized-key .key-comment", "renamed"
  end

  test "offers to delete every key except the Elio key" do
    sign_in users(:one)
    named = Ssh::KeyGenerator.generate(comment: "alice@laptop").public_key

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(ssh_keys(:main).public_key, named))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select "li.authorized-key:nth-child(1) form", 0
    assert_select "li.authorized-key:nth-child(2) form[action=?][data-turbo-confirm][data-turbo-frame=_top]", server_authorized_key_path(servers(:web)) do
      assert_select "input[name=_method][value=delete]"
      assert_select "input[name=key][value=?]", named.split(" ")[1]
      assert_select "input[name=name][value=?]", "alice@laptop"
      assert_select "button[title=?] svg", "Supprimer la clé"
    end
  end

  test "destroy requires authentication" do
    delete server_authorized_key_path(servers(:web)), params: { key: "AAAA" }
    assert_redirected_to new_user_session_path
  end

  test "destroy requires a key" do
    sign_in users(:one)
    delete server_authorized_key_path(servers(:web))
    assert_response :bad_request
  end

  test "destroy removes the key and reloads the list over Turbo Stream" do
    sign_in users(:one)
    removed = Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil)

    stub_method(Keys::AuthorizedKeyRemoval, :call, removed) do
      delete server_authorized_key_path(servers(:web)), params: { key: "AAAA", name: "alice@laptop" }, as: :turbo_stream
    end

    assert_response :success
    assert_turbo_stream action: :replace, target: frame_id do
      assert_select "turbo-frame[loading=eager][src=?]", server_authorized_keys_path(servers(:web))
    end
    assert_turbo_stream action: :update, target: "flash" do
      assert_select "div", text: "La clé « alice@laptop » a été supprimée de « Web »."
    end
  end

  test "destroy reports a key that was already gone, unnamed" do
    sign_in users(:one)
    absent = Keys::AuthorizedKeyRemoval::Result.new(status: :absent, error_title: nil, error_details: nil)

    stub_method(Keys::AuthorizedKeyRemoval, :call, absent) do
      delete server_authorized_key_path(servers(:web)), params: { key: "AAAA" }, as: :turbo_stream
    end

    assert_turbo_stream action: :update, target: "flash" do
      assert_select "div", text: "La clé « sans nom » n'était plus présente sur « Web »."
    end
  end

  test "destroy refuses the Elio key" do
    sign_in users(:one)

    delete server_authorized_key_path(servers(:web)), params: { key: ssh_keys(:main).public_key.split(" ")[1], name: "elio" }, as: :turbo_stream

    assert_turbo_stream action: :update, target: "flash" do
      assert_select "div.toast-alert", text: /Suppression interdite/
    end
  end

  test "destroy HTML fallback redirects to the server page" do
    sign_in users(:one)
    removed = Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil)

    stub_method(Keys::AuthorizedKeyRemoval, :call, removed) do
      delete server_authorized_key_path(servers(:web)), params: { key: "AAAA", name: "bob" }
    end

    assert_redirected_to server_path(servers(:web), tab: "keys")
    assert_response :see_other
  end

  test "reads the login user's file" do
    sign_in users(:one)
    accounts = []
    reader = lambda do |_server, account:, **|
      accounts << account
      keys_result
    end

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(reader)) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_equal [ "deploy" ], accounts.map(&:unix_user)
    assert_select "code", "~deploy/.ssh/authorized_keys"
    assert_select "nav.account-tabs", 0
  end

  test "shows when a temporary access expires" do
    sign_in users(:one)
    access = create_temporary_access(expires_at: 9.minutes.from_now + 30.seconds)
    type, blob = public_keys(:ci).content.split(" ")

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(%(expiry-time="20300101000000Z" #{type} #{blob} CI), public_keys(:alice).content))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select "li.authorized-key:nth-child(1) .key-expiry[title=?]", I18n.l(access.expires_at, format: :long), text: /Expire dans 10 minutes/
    assert_select "li.authorized-key:nth-child(2) .key-expiry", 0
  end

  test "flags an expired access waiting for its removal" do
    sign_in users(:one)
    create_temporary_access(expires_at: 1.minute.ago)

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(public_keys(:ci).content))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select ".key-expiry", text: /Expiré, suppression en cours/
  end

  test "destroy ends the temporary access of the removed key" do
    sign_in users(:one)
    access = create_temporary_access
    other = create_temporary_access(server: servers(:db), unix_user: "admin")
    removed = Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil)

    stub_method(Keys::AuthorizedKeyRemoval, :call, removed) do
      delete server_authorized_key_path(servers(:web)), params: { key: public_keys(:ci).authorized_key.key }, as: :turbo_stream
    end

    assert_not access.reload.active?
    assert other.reload.active?
  end

  test "destroy keeps the temporary access when the removal fails" do
    sign_in users(:one)
    access = create_temporary_access
    failed = Keys::AuthorizedKeyRemoval::Result.new(status: :error, error_title: "Connexion impossible", error_details: "")

    stub_method(Keys::AuthorizedKeyRemoval, :call, failed) do
      delete server_authorized_key_path(servers(:web)), params: { key: public_keys(:ci).authorized_key.key }, as: :turbo_stream
    end

    assert access.reload.active?
  end

  test "highlights the unknown keys and offers to add them to the keyring" do
    sign_in users(:one)
    unnamed = Ssh::KeyGenerator.generate.public_key.split(" ").first(2).join(" ")
    bob = Ssh::KeyGenerator.generate(comment: "bob@desktop").public_key
    ci_unnamed = public_keys(:ci).content.split(" ").first(2).join(" ")

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(ssh_keys(:main).public_key, unnamed, %(no-pty #{bob}), ci_unnamed))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select ".orphan-warning", text: /2 clés ne sont pas dans le trousseau/
    assert_select "li.authorized-key.is-orphan", 2
    assert_select "li.authorized-key:nth-child(1) a.add-to-keyring", 0
    assert_select "li.authorized-key:nth-child(4) a.add-to-keyring", 0
    return_to = server_path(servers(:web), tab: "keys")
    assert_select "li.authorized-key:nth-child(2) a.add-to-keyring[data-turbo-frame=_top][href=?]",
                  new_public_key_path(content: unnamed, return_to: return_to), text: /Ajouter au trousseau/
    assert_select "li.authorized-key:nth-child(3) a.add-to-keyring[href=?]",
                  new_public_key_path(content: bob, name: "bob", return_to: return_to)
  end

  test "no warning when every key is identified" do
    sign_in users(:one)

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(ssh_keys(:main).public_key, public_keys(:alice).content))) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select ".orphan-warning", 0
    assert_select "li.is-orphan", 0
    assert_select "a.add-to-keyring", 0
  end

  test "records the snapshot and the SSH status on a successful read" do
    sign_in users(:one)

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(public_keys(:alice).content))) do
      get server_authorized_keys_path(servers(:web))
    end

    snapshot = AccountSnapshot.find_by!(server: servers(:web), unix_user: "deploy")
    assert_equal [ public_keys(:alice).fingerprint ], snapshot.fingerprints
    assert servers(:web).reload.ssh_ok
  end

  test "records a refused key and guides the user to install the Elio key" do
    sign_in users(:one)
    refused = Keys::AuthorizedKeysReader::Result.new(keys: [], error_title: "Clé SSH refusée par le serveur", error_details: "x", reason: :key_refused)

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(refused)) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_equal false, servers(:web).reload.ssh_ok
    assert_select ".ssh-setup-hint textarea", text: /#{Regexp.escape(ssh_keys(:main).public_key)}/
    assert_select "a.retry-authorized-keys[href=?]", server_authorized_keys_path(servers(:web))
    assert_equal 0, AccountSnapshot.count
  end

  test "points to the settings when there is no Elio key" do
    sign_in users(:one)
    missing = Keys::AuthorizedKeysReader::Result.new(keys: [], error_title: "Aucune clé SSH configurée", error_details: "x", reason: :missing_key)

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(missing)) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select ".ssh-setup-hint a[href=?][data-turbo-frame=_top]", settings_path
    assert_nil servers(:web).reload.ssh_ok
  end

  test "destroy logs the removed key" do
    sign_in users(:one)
    removed = Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil)

    stub_method(Keys::AuthorizedKeyRemoval, :call, removed) do
      delete server_authorized_key_path(servers(:web)), params: { key: "AAAA", name: "bob" }, as: :turbo_stream
    end

    activity = Activity.of_kind(:key_removed).sole
    assert_equal [ "deploy", "bob", users(:one) ], [ activity.unix_user, activity.key_name, activity.user ]
  end

  test "keeps the type, fingerprint and options out of the rows, in a details modal" do
    sign_in users(:one)
    line = %(no-pty #{public_keys(:alice).content})

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(line))) do
      get server_authorized_keys_path(servers(:web))
    end

    key = AuthorizedKey.parse(line).sole
    assert_select "li.authorized-key" do
      assert_select "[data-controller=modal] button.key-details-button[data-action='modal#open'][title=?]", "Détails de la clé"
      assert_select "dialog.key-details[data-modal-target=dialog]" do
        assert_select "h2", "alice@laptop"
        assert_select "p", "~deploy/.ssh/authorized_keys"
        assert_select ".key-fingerprint", key.fingerprint
        assert_select ".key-options", "no-pty"
        assert_select "dd a[href=?][data-turbo-frame=_top]", public_key_path(public_keys(:alice)), text: "Alice"
        assert_select "dd", text: "n° 1 du fichier"
        assert_select "[data-controller=clipboard] textarea", line
        assert_select "button[data-action='modal#close'][aria-label=Fermer]"
      end
    end
    assert_select "li.authorized-key > div:first-of-type p", 0
  end

  test "each key gets its own dialog ids" do
    sign_in users(:one)

    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(public_keys(:alice).content, public_keys(:ci).content))) do
      get server_authorized_keys_path(servers(:web))
    end

    ids = css_select("dialog.key-details textarea").map { |textarea| textarea["id"] }
    assert_equal 2, ids.uniq.size
  end

  test "with root, one section per account, each key removable from its account" do
    sign_in users(:one)
    bob = Ssh::KeyGenerator.generate(comment: "bob").public_key
    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(ssh_keys(:main).public_key), others: { "root" => [ bob, public_keys(:alice).content ] })) do
      get server_authorized_keys_path(servers(:web))
    end

    assert_select "turbo-frame##{frame_id}" do
      assert_select "p", text: /2 comptes · 3 clés/
      assert_select "section.authorized-keys-account", 2
      assert_select "section.authorized-keys-account[data-account=deploy]" do
        assert_select "h3 .account-login"
        assert_select "li.authorized-key .key-master"
      end
      assert_select "section.authorized-keys-account[data-account=root]" do
        assert_select "h3 code", "~root/.ssh/authorized_keys"
        assert_select "h3 .account-login", 0
        assert_select ".orphan-warning"
        assert_select "li.authorized-key form input[name=account][value=root]", 2
        assert_select "li.authorized-key form[data-turbo-confirm*='compte root']", 2
      end
      assert_select ".accounts-root-needed", 0
    end
    assert_equal %w[deploy root], servers(:web).account_snapshots.order(:unix_user).pluck(:unix_user)
  end

  test "without root, only the login account and a note" do
    sign_in users(:one)
    stub_method(Keys::AuthorizedKeysReader, :call_all, keys_read(keys_result(public_keys(:alice).content))) do
      get server_authorized_keys_path(servers(:web))
    end
    assert_select "section.authorized-keys-account", 1
    assert_select "section.authorized-keys-account h3", 0
    assert_select ".accounts-root-needed", /Seules les clés de deploy/
  end

  test "removing a key from another account" do
    sign_in users(:one)
    calls = []
    removal = lambda do |server, blob, account:, **|
      calls << [ server, blob, account.unix_user ]
      Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil)
    end

    stub_method(Keys::AuthorizedKeyRemoval, :call, removal) do
      delete server_authorized_key_path(servers(:web)), params: { key: "AAAA", name: "bob", account: "root" }, as: :turbo_stream
    end

    assert_equal [ [ servers(:web), "AAAA", "root" ] ], calls
    assert_match "supprimée de « Web » (compte root)", response.body
    activity = Activity.of_kind(:key_removed).last
    assert_equal "root", activity.unix_user
    assert_equal "Clé « bob » supprimée de « Web » (compte root)", activity.summary

    sign_in users(:one)
    delete server_authorized_key_path(servers(:web)), params: { key: "AAAA", account: "bad name" }
    assert_response :unprocessable_content
  end
end
