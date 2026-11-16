require "test_helper"

class PublicKeyAccessesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include TemporaryAccessHelpers

  setup do
    @public_key = public_keys(:alice)
    @grants = []
    # After a grant, the controller re-reads the account to refresh its snapshot.
    stub_method_until_teardown(Keys::AuthorizedKeysReader, :call, ->(*, **) { Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(@public_key.content), error_title: nil, error_details: nil) })
  end

  def granter(status_for = ->(_server) { :added })
    lambda do |server, public_key, account:, duration:, **|
      @grants << [ server.name, public_key.name, account.unix_user, duration ]
      status = status_for.call(server)
      Keys::PublicKeyAuthorization::Result.new(status: status, error_title: (status == :error ? "Connexion impossible" : nil), error_details: (status == :error ? "refused" : nil))
    end
  end

  test "requires authentication" do
    post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id ] }
    assert_redirected_to new_user_session_path

    delete public_key_access_path(@public_key), params: { server_id: servers(:web).id }
    assert_redirected_to new_user_session_path
  end

  test "grants the public_key on another account of each server, the account name checked" do
    sign_in users(:one)
    stub_method_until_teardown(Keys::ServerScan, :call, ->(*, **) { Keys::ServerScan::Result.new(error_title: nil) })

    stub_method(Keys::AccessGrant, :call, granter) do
      post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id, servers(:db).id ], unix_user: "www-app" }, as: :turbo_stream
      post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id ], unix_user: "../root" }
    end

    assert_equal [ [ "Database", "Alice", "www-app", nil ], [ "Web", "Alice", "www-app", nil ] ], @grants
    assert_match "Nom de compte invalide", flash[:alert]
  end

  test "grants the public_key on each selected server's login user" do
    sign_in users(:one)

    stub_method(Keys::AccessGrant, :call, granter) do
      post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id, servers(:db).id ] }, as: :turbo_stream
    end

    assert_equal [ [ "Database", "Alice", "admin", nil ], [ "Web", "Alice", "deploy", nil ] ], @grants
    assert_turbo_stream action: :update, target: "bulk-results" do
      assert_select "li.bulk-result.is-success", 2
      assert_select "li.bulk-result", text: "Web · deploy : ajoutée"
    end
    assert_turbo_stream action: :replace, target: "key-accesses" do
      assert_select "li.key-access", 2
    end
    assert_turbo_stream action: :update, target: "flash" do
      assert_select ".toast-notice", text: "Ajouts terminés : 2/2 serveurs."
    end
    assert_equal 2, AccountSnapshot.count
  end

  test "grants for a limited time" do
    sign_in users(:one)

    stub_method(Keys::AccessGrant, :call, granter) do
      post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id ], duration: "60" }, as: :turbo_stream
    end

    assert_equal [ [ "Web", "Alice", "deploy", 1.hour ] ], @grants
    assert_turbo_stream action: :update, target: "bulk-results" do
      assert_select "li.bulk-result", text: "Web · deploy : ajoutée pendant 1 heure"
    end
  end

  test "reports each server's outcome" do
    sign_in users(:one)
    statuses = { "Web" => :already_present, "Database" => :error }

    stub_method(Keys::AccessGrant, :call, granter(->(server) { statuses.fetch(server.name) })) do
      post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id, servers(:db).id ] }, as: :turbo_stream
    end

    assert_turbo_stream action: :update, target: "bulk-results" do
      assert_select "li.bulk-result.is-success", text: "Web · deploy : déjà présente"
      assert_select "li.bulk-result.is-error", text: "Database · admin : Connexion impossible — refused"
    end
    assert_turbo_stream action: :update, target: "flash" do
      assert_select ".toast-notice", text: /1\/2/
    end
    assert_equal 1, AccountSnapshot.count
  end

  test "offers to retry only the failed servers, with the same duration and account" do
    sign_in users(:one)
    stub_method_until_teardown(Keys::ServerScan, :call, ->(*, **) { Keys::ServerScan::Result.new(error_title: nil) })
    statuses = { "Web" => :added, "Database" => :error }

    stub_method(Keys::AccessGrant, :call, granter(->(server) { statuses.fetch(server.name) })) do
      post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id, servers(:db).id ], duration: "60", unix_user: "www-app" }, as: :turbo_stream
    end

    assert_turbo_stream action: :update, target: "bulk-results" do
      assert_select "form.bulk-retry[action=?]", public_key_accesses_path(@public_key) do
        assert_select "input[name='server_ids[]']", 1
        assert_select "input[name='server_ids[]'][value=?]", servers(:db).id.to_s
        assert_select "input[name=duration][value='60']"
        assert_select "input[name=unix_user][value='www-app']"
        assert_select "button", text: "Relancer l'échec"
      end
    end
  end

  test "no retry button when every server succeeded" do
    sign_in users(:one)

    stub_method(Keys::AccessGrant, :call, granter) do
      post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id ] }, as: :turbo_stream
    end

    assert_turbo_stream action: :update, target: "bulk-results" do
      assert_select "form.bulk-retry", 0
    end
  end

  test "removes the key from every known account, each outcome reported, with a retry of the failures" do
    sign_in users(:one)
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(@public_key.content))
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.new(servers(:web), "www-app"), AuthorizedKey.parse(@public_key.content))
    AccountSnapshot.record!(servers(:db), AuthorizedKeysAccount.login(servers(:db)), AuthorizedKey.parse(@public_key.content))
    calls = []
    remover = lambda do |server, blob, account:, **|
      calls << [ server.name, blob, account.unix_user ]
      status = server == servers(:db) ? :error : :removed
      Keys::AuthorizedKeyRemoval::Result.new(status: status, error_title: (status == :error ? "Connexion impossible" : nil), error_details: (status == :error ? "refused" : nil))
    end

    stub_method(Keys::AuthorizedKeyRemoval, :call, remover) do
      delete public_key_accesses_path(@public_key), as: :turbo_stream
    end

    blob = @public_key.authorized_key.key
    assert_equal [ [ "Database", blob, "admin" ], [ "Web", blob, "deploy" ], [ "Web", blob, "www-app" ] ], calls.sort
    assert_equal [ "admin" ], AccountSnapshot.with_fingerprint(@public_key.fingerprint).map(&:unix_user)
    assert_equal 2, Activity.of_kind(:key_removed).count
    assert_turbo_stream action: :replace, target: "key-accesses" do
      assert_select "li.key-access", 1
    end
    assert_turbo_stream action: :update, target: "revoke-results" do
      assert_select "li.bulk-result.is-success", text: "Web · deploy : retirée"
      assert_select "li.bulk-result.is-error", text: "Database · admin : Connexion impossible — refused"
      assert_select "form.bulk-retry[action=?]", public_key_accesses_path(@public_key) do
        assert_select "input[name=_method][value=delete]"
      end
    end
    assert_turbo_stream action: :update, target: "flash" do
      assert_select ".toast-alert", text: "Retraits terminés : 2/3 comptes."
    end
  end

  test "removing everywhere without any known access says so" do
    sign_in users(:one)

    delete public_key_accesses_path(@public_key), as: :turbo_stream

    assert_turbo_stream action: :update, target: "flash" do
      assert_select ".toast-alert", text: "Aucun accès connu à retirer."
    end
  end

  test "removing everywhere needs the operate permission" do
    sign_in users(:viewer)

    stub_method(Keys::BulkAccess, :revoke, ->(*) { flunk "must not revoke" }) do
      delete public_key_accesses_path(@public_key)
    end

    assert_response :forbidden
  end

  test "asks to choose a server" do
    sign_in users(:one)

    post public_key_accesses_path(@public_key), params: {}

    assert_redirected_to public_key_path(@public_key)
    assert_equal "Choisissez au moins un serveur.", flash[:alert]
  end

  test "rejects a duration that is not offered" do
    sign_in users(:one)
    post public_key_accesses_path(@public_key), params: { server_ids: [ servers(:web).id ], duration: "3" }
    assert_response :bad_request
  end

  test "revokes one access and updates the snapshot and temporary access" do
    sign_in users(:one)
    public_key = public_keys(:ci)
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(public_key.content))
    access = create_temporary_access(public_key: public_key)
    calls = []
    remover = lambda do |server, blob, account:, **|
      calls << [ server, blob, account.unix_user ]
      Keys::AuthorizedKeyRemoval::Result.new(status: :removed, error_title: nil, error_details: nil)
    end

    stub_method(Keys::AuthorizedKeyRemoval, :call, remover) do
      delete public_key_access_path(public_key), params: { server_id: servers(:web).id }, as: :turbo_stream
    end

    assert_equal [ [ servers(:web), public_key.authorized_key.key, "deploy" ] ], calls
    assert_not access.reload.active?
    assert_empty AccountSnapshot.sole.fingerprints
    assert_turbo_stream action: :replace, target: "key-accesses" do
      assert_select "li.key-access", 0
    end
    assert_turbo_stream action: :update, target: "flash" do
      assert_select ".toast-notice", text: "L'accès de « CI » à « Web » a été retiré."
    end
  end

  test "keeps everything when the revocation fails" do
    sign_in users(:one)
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(@public_key.content))
    failed = Keys::AuthorizedKeyRemoval::Result.new(status: :error, error_title: "Connexion impossible", error_details: "refused")

    stub_method(Keys::AuthorizedKeyRemoval, :call, failed) do
      delete public_key_access_path(@public_key), params: { server_id: servers(:web).id }, as: :turbo_stream
    end

    assert_equal [ @public_key.fingerprint ], AccountSnapshot.sole.fingerprints
    assert_turbo_stream action: :update, target: "flash" do
      assert_select ".toast-alert", text: /Impossible de retirer l'accès : Connexion impossible/
    end
  end

  test "the public_key page shows its accesses and the bulk form" do
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(@public_key.content))
    sign_in users(:one)

    get public_key_path(@public_key)

    assert_select "#key-accesses li.key-access", 1 do
      assert_select "a[href=?]", server_path(servers(:web)), text: "Web"
      assert_select "span", text: "Permanent"
      assert_select "form[action=?][data-turbo-confirm][data-confirm-variant=danger]", public_key_access_path(@public_key)
    end
    assert_select "form[action=?][data-turbo-confirm*='du seul compte'] input[name=_method][value=delete]", public_key_accesses_path(@public_key)
    assert_select "#bulk-authorize form[action=?]", public_key_accesses_path(@public_key) do
      assert_select "input[type=checkbox][name='server_ids[]']", 3
      assert_select "input[name=account]", 0
      assert_select "select[name=duration] option[value='60']", "1 heure"
    end
  end

  test "the bulk form can check a whole group (only the groups that have servers)" do
    sign_in users(:one)
    production = server_groups(:production)

    get public_key_path(@public_key)

    assert_select "#bulk-authorize .bulk-groups" do
      assert_select "button[data-action='check-all#toggleGroup'][data-check-all-group-param=?]", production.id.to_s, text: "Production 2"
      assert_select "button", text: /Staging/, count: 0
    end
    assert_select "input#server_ids_#{servers(:web).id}[data-groups=?]", production.id.to_s
    assert_select "input#server_ids_#{servers(:backup).id}[data-groups='']"
  end
end
