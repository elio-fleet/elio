require "test_helper"

class PublicKeysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @key = Ssh::KeyGenerator.generate(comment: "bob@desktop")
  end

  def valid_params
    { public_key: { name: "Bob", content: @key.public_key } }
  end

  test "every action requires authentication" do
    public_key = public_keys(:alice)

    get new_public_key_path
    assert_redirected_to new_user_session_path
    get public_key_path(public_key)
    assert_redirected_to new_user_session_path
    get edit_public_key_path(public_key)
    assert_redirected_to new_user_session_path

    assert_no_difference "PublicKey.count" do
      post public_keys_path, params: valid_params
    end
    assert_redirected_to new_user_session_path

    patch public_key_path(public_key), params: { public_key: { name: "Hacked" } }
    assert_redirected_to new_user_session_path
    assert_equal "Alice", public_key.reload.name

    assert_no_difference "PublicKey.count" do
      delete public_key_path(public_key)
    end
    assert_redirected_to new_user_session_path
  end

  test "new renders the form" do
    sign_in users(:one)
    get new_public_key_path

    assert_response :success
    assert_select "form[action=?]", public_keys_path do
      assert_select "input[name='public_key[name]']"
      assert_select "textarea[name='public_key[content]']"
      assert_select "input[type=submit][value='Ajouter au trousseau']"
    end
  end

  test "create saves the public_key and redirects to its page" do
    sign_in users(:one)

    assert_difference "PublicKey.count", 1 do
      post public_keys_path, params: valid_params
    end

    public_key = PublicKey.find_by!(name: "Bob")
    assert_equal @key.public_key, public_key.content
    assert_equal @key.fingerprint, public_key.fingerprint
    assert_redirected_to public_key_path(public_key)
    assert_equal "La clé « Bob » a été ajoutée au trousseau.", flash[:notice]
  end

  test "create re-renders the form with errors when invalid" do
    sign_in users(:one)

    assert_no_difference "PublicKey.count" do
      post public_keys_path, params: { public_key: { name: "", content: "not a key" } }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", 2
  end

  test "create refuses a private key and does not echo it back" do
    sign_in users(:one)

    assert_no_difference "PublicKey.count" do
      post public_keys_path, params: { public_key: { name: "Oops", content: @key.private_key } }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: /ressemble à une clé privée/
  end

  test "create refuses a key already used by another public_key" do
    sign_in users(:one)

    assert_no_difference "PublicKey.count" do
      post public_keys_path, params: { public_key: { name: "Alice bis", content: public_keys(:alice).content } }
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation li", text: "Cette clé est déjà dans le trousseau"
  end

  test "show displays the public_key and its key" do
    sign_in users(:one)
    public_key = public_keys(:alice)

    get public_key_path(public_key)

    assert_response :success
    assert_select "h1", "Alice"
    assert_select "#keyring-fingerprint", public_key.fingerprint
    assert_select "textarea#keyring-content", public_key.content
    assert_select "dd", text: "alice@laptop"
    assert_select "a[href=?]", edit_public_key_path(public_key)
    assert_select "form[action=?][data-turbo-confirm] input[name=_method][value=delete]", public_key_path(public_key)
  end

  test "show handles a key without a comment" do
    sign_in users(:one)
    get public_key_path(public_keys(:ci))
    assert_select "dd span", text: "Aucun"
  end

  test "show, edit, update and destroy return 404 for an unknown public_key" do
    # A 404 does not persist the session, so sign in again before each request.
    [ -> { get public_key_path(id: 0) },
      -> { get edit_public_key_path(id: 0) },
      -> { patch public_key_path(id: 0), params: { public_key: { name: "x" } } },
      -> { delete public_key_path(id: 0) } ].each do |request|
      sign_in users(:one)
      request.call
      assert_response :not_found
    end
  end

  test "edit renders the form prefilled" do
    sign_in users(:one)
    public_key = public_keys(:alice)

    get edit_public_key_path(public_key)

    assert_response :success
    assert_select "form[action=?]", public_key_path(public_key) do
      assert_select "input[name='public_key[name]'][value='Alice']"
      assert_select "textarea[name='public_key[content]']", public_key.content
      assert_select "input[type=submit][value='Enregistrer']"
    end
  end

  test "update changes the name and the key" do
    sign_in users(:one)
    public_key = public_keys(:alice)

    patch public_key_path(public_key), params: { public_key: { name: "Alice Martin", content: @key.public_key } }

    public_key.reload
    assert_equal "Alice Martin", public_key.name
    assert_equal @key.fingerprint, public_key.fingerprint
    assert_redirected_to public_key_path(public_key)
    assert_equal "La clé « Alice Martin » a été modifiée.", flash[:notice]
  end

  test "update re-renders the form with errors when invalid" do
    sign_in users(:one)
    public_key = public_keys(:alice)

    patch public_key_path(public_key), params: { public_key: { name: "CI" } }

    assert_response :unprocessable_entity
    assert_select "h1", text: "Modifier « Alice »"
    assert_equal "Alice", public_key.reload.name
  end

  test "destroy deletes the public_key and redirects to the public_keys" do
    sign_in users(:one)

    assert_difference "PublicKey.count", -1 do
      delete public_key_path(public_keys(:alice))
    end

    assert_redirected_to public_keys_path
    assert_response :see_other
    assert_equal "La clé « Alice » a été retirée du trousseau.", flash[:notice]
  end

  test "new can be prefilled from a server key, with a way back" do
    sign_in users(:one)

    get new_public_key_path(content: @key.public_key, name: "bob", return_to: "/servers/1#server-authorized-keys")

    assert_select "p.prefilled-hint"
    assert_select "a[href=?]", "/servers/1#server-authorized-keys", text: "← Retour au serveur"
    assert_select "form[action=?]", public_keys_path do
      assert_select "input[name='public_key[name]'][value=bob]"
      assert_select "textarea[name='public_key[content]']", @key.public_key
      assert_select "input[type=hidden][name=return_to][value=?]", "/servers/1#server-authorized-keys"
      assert_select "a[href=?]", "/servers/1#server-authorized-keys", text: "Annuler"
    end
  end

  test "create goes back to the given local path" do
    sign_in users(:one)

    post public_keys_path, params: valid_params.merge(return_to: server_path(servers(:web), tab: "keys"))

    assert_redirected_to server_path(servers(:web), tab: "keys")
  end

  test "create ignores a return path to another site" do
    [ "https://evil.example", "//evil.example", "/\\evil.example", "javascript:alert(1)" ].each_with_index do |return_to, index|
      sign_in users(:one)
      post public_keys_path, params: { public_key: { name: "Bob #{index}", content: Ssh::KeyGenerator.generate.public_key }, return_to: return_to }
      assert_redirected_to public_key_path(PublicKey.find_by!(name: "Bob #{index}")), "#{return_to} should be ignored"
    end
  end

  test "new without a return path keeps the usual links" do
    sign_in users(:one)
    get new_public_key_path(return_to: "https://evil.example")

    assert_select "a[href=?]", public_keys_path, text: "← Clés SSH"
    assert_select "input[name=return_to]", 0
  end

  test "logs the created and deleted public_keys" do
    sign_in users(:one)

    post public_keys_path, params: valid_params
    delete public_key_path(PublicKey.find_by!(name: "Bob"))

    assert_equal [ "Clé « Bob » ajoutée au trousseau", "Clé « Bob » retirée du trousseau" ], Activity.order(:id).map(&:summary)
  end

  test "the form asks for the kind and an optional description" do
    sign_in users(:one)
    get new_public_key_path(kind: "server")

    assert_select "input[type=radio][name='public_key[kind]'][value=person]"
    assert_select "input[type=radio][name='public_key[kind]'][value=server][checked]"
    assert_select "input[name='public_key[description]']"
  end

  test "create saves the kind and the description" do
    sign_in users(:one)

    post public_keys_path, params: { public_key: { name: "Backup", kind: "server", description: "Serveur de sauvegarde", content: @key.public_key } }

    public_key = PublicKey.find_by!(name: "Backup")
    assert_equal [ "server", "Serveur de sauvegarde" ], [ public_key.kind, public_key.description ]
    follow_redirect!
    assert_select ".key-kind", "Serveur"
    assert_select ".key-description", "Serveur de sauvegarde"
  end
end
