require "test_helper"

# "Ajouter une clé" on the server's keys tab: a key of the keyring, or a new
# key saved to the keyring and added in one go.
class ServerAddKeyTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier
  include StubHelpers

  def added = Keys::PublicKeyAuthorization::Result.new(status: :added, error_title: nil, error_details: nil)

  def new_key_params(duration: "", **overrides)
    { source: "new", duration: duration, public_key: { name: "Bob", kind: "person", content: Ssh::KeyGenerator.generate(comment: "bob@laptop").public_key,
                                                  description: "Portable" }.merge(overrides) }
  end

  test "the keys tab always offers the dialog, with the keyring keys and a duration" do
    AccountSnapshot.record!(servers(:web), AuthorizedKeysAccount.login(servers(:web)), AuthorizedKey.parse(public_keys(:alice).content))
    sign_in users(:operator)

    get server_path(servers(:web), tab: "keys")

    assert_select "##{dom_id(servers(:web), :add_key)}.add-key[data-controller=modal]" do
      assert_select "button.add-key-button", text: /Ajouter une clé/
      assert_select "dialog form[action=?]", server_authorizations_path(servers(:web)) do
        assert_select "input[type=radio][name=source][value=keyring][checked]"
        assert_select "input[type=radio][name=source][value=new]"
        assert_select "select[name=public_key_id] option", PublicKey.count
        assert_select "select[name=public_key_id] option[disabled][value=?]", public_keys(:alice).id.to_s, text: /Alice.*déjà sur le serveur/
        assert_select "select[name=public_key_id] option[selected][value=?]", public_keys(:ci).id.to_s
        assert_select "input[name='public_key[name]'][required]"
        assert_select "textarea[name='public_key[content]'][required]"
        assert_select "input[type=radio][name='public_key[kind]'][value=person][checked]"
        assert_select "select[name=duration] option:first-child[value='']", "Permanent"
        assert_select "select[name=duration] option[value='10080']", "7 jours"
      end
    end
  end

  test "with an empty keyring, the dialog starts on a new key" do
    PublicKey.delete_all
    sign_in users(:one)

    get server_path(servers(:web), tab: "keys")

    assert_select "input[name=source][value=keyring][disabled]"
    assert_select "input[name=source][value=new][checked]"
  end

  test "a new key is saved to the keyring then added to the server" do
    sign_in users(:operator)
    params = new_key_params(duration: "60")
    stub_key_write_session(params[:public_key][:content])
    granted = []

    assert_difference -> { PublicKey.count } do
      stub_method(Keys::AccessGrant, :call, ->(server, public_key, **options) { granted << [ server, public_key.name, options[:duration] ] && added }) do
        post server_authorizations_path(servers(:web)), params: params, as: :turbo_stream
      end
    end

    bob = PublicKey.find_by!(name: "Bob")
    assert_equal [ "person", "Portable" ], [ bob.kind, bob.description ]
    assert_equal [ [ servers(:web), "Bob", 1.hour ] ], granted
    assert Activity.of_kind(:public_key_created).exists?(public_key: bob)
    assert_select "turbo-stream[action=replace][target=?]", dom_id(servers(:web), :authorized_keys)
    assert_select "turbo-stream[action=replace][target=?] template .add-key:not([data-modal-open-value])", dom_id(servers(:web), :add_key)
    assert_select "turbo-stream[action=update][target=flash]", text: /La clé « Bob » \(ajoutée au trousseau\) est ajoutée sur « Web » pendant 1 heure/
  end

  test "an invalid new key shows the dialog again, open, with the errors and the input" do
    sign_in users(:one)

    assert_no_difference -> { PublicKey.count } do
      stub_method(Keys::AccessGrant, :call, ->(*) { flunk "nothing must be added" }) do
        post server_authorizations_path(servers(:web)), params: new_key_params(name: "Bob", content: "pas une clé"), as: :turbo_stream
      end
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target=?]", dom_id(servers(:web), :add_key) do
      assert_select "template .add-key[data-modal-open-value=true]"
      assert_select "template input[name=source][value=new][checked]"
      assert_select "template input[name='public_key[name]'][value=Bob]"
      assert_select "template textarea[name='public_key[content]']", "pas une clé"
      assert_select "template #error_explanation, template [role=alert], template .form-errors", minimum: 1
    end
  end

  test "an invalid new key without Turbo goes back to the keys tab with the errors" do
    sign_in users(:one)
    post server_authorizations_path(servers(:web)), params: new_key_params(content: "")
    assert_redirected_to server_path(servers(:web), tab: "keys")
    assert_match "Clé non enregistrée", flash[:alert]
  end

  test "when the server refuses, the new key stays in the keyring" do
    sign_in users(:one)
    stub_key_write_session
    failed = Keys::PublicKeyAuthorization::Result.new(status: :error, error_title: "Connexion impossible", error_details: "refusée")

    stub_method(Keys::AccessGrant, :call, failed) do
      post server_authorizations_path(servers(:web)), params: new_key_params, as: :turbo_stream
    end

    assert PublicKey.exists?(name: "Bob")
    assert_select "turbo-stream[action=update][target=flash]", text: /Impossible d'ajouter « Bob » sur « Web » \(elle reste dans le trousseau\) : Connexion impossible/
  end

  test "viewers cannot add a new key" do
    sign_in users(:viewer)
    assert_no_difference -> { PublicKey.count } do
      post server_authorizations_path(servers(:web)), params: new_key_params
    end
    assert_response :forbidden
  end
end
