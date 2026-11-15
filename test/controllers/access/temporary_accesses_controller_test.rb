require "test_helper"

class TemporaryAccessesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include TemporaryAccessHelpers

  def extended = Keys::AccessExtension::Result.new(status: :extended, error_title: nil, error_details: nil)

  test "lists the accesses in progress and the ended ones of the server only" do
    create_temporary_access(expires_at: 2.hours.from_now).update!(extensions_count: 1)
    create_temporary_access(public_key: public_keys(:alice), unix_user: "root", expires_at: 1.hour.ago).tap(&:end!)
    create_temporary_access(public_key: public_keys(:alice), expires_at: 1.hour.from_now).tap(&:end!)
    create_temporary_access(server: servers(:db))
    sign_in users(:viewer)

    get server_temporary_accesses_path(servers(:web))

    assert_response :success
    assert_select "#active-temporary-accesses .temporary-access", 1 do
      assert_select "a", "CI"
      assert_select "*", text: /prolongé une fois/
    end
    assert_select ".extend-access", 0, "a viewer cannot extend"
    assert_select ".past-temporary-access", 2
    assert_select ".past-temporary-access", text: /Expiré/
    assert_select ".past-temporary-access", text: /Retiré ou remplacé avant son terme/
  end

  test "an operator extends an access by the chosen duration" do
    access = create_temporary_access(expires_at: 30.minutes.from_now)
    sign_in users(:operator)
    calls = []

    stub_method(Keys::AccessExtension, :call, ->(record, duration) { calls << [ record, duration ]; extended }) do
      get server_temporary_accesses_path(servers(:web))
      assert_select ".extend-access select[name=duration]"

      patch server_temporary_access_path(servers(:web), access), params: { duration: "240" }
    end

    assert_equal [ [ access, 4.hours ] ], calls
    assert_redirected_to server_temporary_accesses_path(servers(:web))
    assert_match "CI sur deploy : prolongé de 4 heures", flash[:notice]
  end

  test "a refused extension is reported; an unknown duration is a bad request; another server's access is not found" do
    access = create_temporary_access
    sign_in users(:operator)
    failed = Keys::AccessExtension::Result.new(status: :error, error_title: "Clé introuvable", error_details: "Rafraîchissez.")

    stub_method(Keys::AccessExtension, :call, ->(*) { failed }) do
      patch server_temporary_access_path(servers(:web), access), params: { duration: "60" }
    end
    assert_equal "Accès non prolongé : Clé introuvable. Rafraîchissez.", flash[:alert]

    stub_method(Keys::AccessExtension, :call, ->(*) { flunk "no extension" }) do
      patch server_temporary_access_path(servers(:web), access), params: { duration: "5" }
      assert_response :bad_request

      sign_in users(:operator)
      patch server_temporary_access_path(servers(:db), access), params: { duration: "60" }
      assert_response :not_found
    end
  end
end
