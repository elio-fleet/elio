require "test_helper"

class ServerAuthorizationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier
  include StubHelpers
  include TcpHelpers
  include TemporaryAccessHelpers

  def result(status, title: nil, details: nil)
    Keys::PublicKeyAuthorization::Result.new(status: status, error_title: title, error_details: details)
  end

  test "requires authentication" do
    post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id }
    assert_redirected_to new_user_session_path
  end

  test "returns 404 for an unknown server or public_key" do
    sign_in users(:one)
    post server_authorizations_path(server_id: 0), params: { public_key_id: public_keys(:alice).id }
    assert_response :not_found

    sign_in users(:one)
    post server_authorizations_path(servers(:web)), params: { public_key_id: 0 }
    assert_response :not_found
  end

  test "requires a public_key" do
    sign_in users(:one)
    post server_authorizations_path(servers(:web))
    assert_response :bad_request
  end

  test "authorizes the public_key and reloads the key list over Turbo Stream" do
    sign_in users(:one)

    stub_method(Keys::PublicKeyAuthorization, :call, result(:added)) do
      post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id }, as: :turbo_stream
    end

    assert_response :success
    assert_turbo_stream action: :replace, target: dom_id(servers(:web), :authorized_keys) do
      assert_select "turbo-frame[loading=eager][src=?]", server_authorized_keys_path(servers(:web))
    end
    assert_turbo_stream action: :update, target: "flash" do
      assert_select "div", text: "La clé « Alice » a été ajoutée sur « Web »."
    end
  end

  test "reports a public_key that was already authorized" do
    sign_in users(:one)

    stub_method(Keys::PublicKeyAuthorization, :call, result(:already_present)) do
      post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id }, as: :turbo_stream
    end

    assert_turbo_stream action: :update, target: "flash" do
      assert_select "div", text: "La clé « Alice » était déjà présente sur « Web »."
    end
  end

  test "shows the error as an alert" do
    Server.update_all(host: "127.0.0.1", port: closed_port)
    sign_in users(:one)

    post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id }, as: :turbo_stream

    assert_turbo_stream action: :update, target: "flash" do
      assert_select "div.toast-alert", text: /Impossible d'ajouter « Alice » sur « Web » : Connexion impossible/
    end
  end

  test "the HTML fallback redirects to the server page" do
    sign_in users(:one)

    stub_method(Keys::PublicKeyAuthorization, :call, result(:added)) do
      post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id }
    end

    assert_redirected_to server_path(servers(:web), tab: "keys")
    assert_equal "La clé « Alice » a été ajoutée sur « Web ».", flash[:notice]
  end

  test "grants a temporary access for the requested duration" do
    sign_in users(:one)
    calls = []
    granter = lambda do |_server, public_key, account:, duration:, **|
      calls << [ public_key, account.unix_user, duration ]
      result(:added)
    end

    freeze_time do
      stub_method(Keys::AccessGrant, :call, granter) do
        post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id, duration: "10" }, as: :turbo_stream
      end

      assert_equal [ [ public_keys(:alice), "deploy", 10.minutes ] ], calls
      assert_turbo_stream action: :update, target: "flash" do
        assert_select "div", text: "La clé « Alice » est ajoutée sur « Web » pendant 10 minutes, jusqu'à #{I18n.l(10.minutes.from_now, format: :short)}."
      end
    end
  end

  test "a blank duration means a permanent access" do
    sign_in users(:one)
    durations = []

    stub_method(Keys::AccessGrant, :call, ->(*, duration:, **) { durations << duration; result(:added) }) do
      post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id, duration: "" }, as: :turbo_stream
    end

    assert_equal [ nil ], durations
  end

  test "rejects a duration that is not offered" do
    sign_in users(:one)
    post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id, duration: "5" }
    assert_response :bad_request
  end

  test "adds the key to the account chosen, a listed one or another one typed in" do
    sign_in users(:one)
    accounts = []
    stub_method(Keys::AccessGrant, :call, ->(_server, _key, account:, **) { accounts << account.unix_user; result(:added) }) do
      post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id, account: "root" }, as: :turbo_stream
      assert_turbo_stream action: :update, target: "flash" do
        assert_select "div", text: /ajoutée sur « Web \(root\) »/
      end
      post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id, account: "other", other_account: " www-app " }, as: :turbo_stream
      post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id }, as: :turbo_stream
    end
    assert_equal %w[root www-app deploy], accounts
  end

  test "refuses an invalid account name without connecting" do
    sign_in users(:one)
    stub_method(Keys::AccessGrant, :call, ->(*) { flunk "no grant" }) do
      post server_authorizations_path(servers(:web)), params: { public_key_id: public_keys(:alice).id, account: "other", other_account: "bob; rm -rf /" }
    end
    assert_redirected_to server_path(servers(:web), tab: "keys")
    assert_match "Nom de compte invalide", flash[:alert]
  end

  test "the dialog offers the accounts Elio read, the other ones disabled without root" do
    AccountSnapshot.create!(server: servers(:web), unix_user: "root", content: "", read_at: Time.current)
    AccountSnapshot.create!(server: servers(:web), unix_user: "bob", content: "", read_at: Time.current)
    sign_in users(:one)

    get server_path(servers(:web), tab: "keys")
    assert_select ".add-key-account select[name=account] option", 4
    assert_select ".add-key-account select[name=account] option[selected][value=deploy]", text: "deploy (connexion d'Elio)"
    assert_select ".add-key-account select[name=account] option:not([disabled])", 4
    assert_select ".add-key-account input[name=other_account]"

    servers(:web).update!(privilege: "none")
    get server_path(servers(:web), tab: "keys")
    assert_select ".add-key-account select[name=account] option[disabled]", 3
    assert_select ".add-key-account p", text: /n'a pas root/
  end
end
