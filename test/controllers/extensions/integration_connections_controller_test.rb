require "test_helper"

class IntegrationConnectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include IntegrationHelpers

  def run(...)
    with_integrations("demo" => "DemoIntegration", "demo_multi" => "DemoMultiIntegration") { super }
  end

  setup { sign_in users(:one) }

  def values(url: "https://coolify.example/team-alpha", token: "new-token") = { connection: { name: "", values: { url: url, token: token } } }

  test "admins only" do
    sign_in users(:operator)
    get new_settings_integration_connection_path("demo_multi")
    assert_response :forbidden
    post settings_integration_connections_path("demo_multi"), params: values
    assert_response :forbidden
  end

  test "only for an extension with several connections" do
    get new_settings_integration_connection_path("demo")
    assert_response :not_found
    sign_in users(:one)
    get new_settings_integration_connection_path("nope")
    assert_response :not_found
  end

  test "the extension page lists the connections by group, without their secrets, and hides its own test button" do
    integration = enable_demo_multi("https://one.example/team-alpha", "https://one.example/team-beta", "https://two.example/team-gamma")
    integration.connections.first.sync!
    integration.connections.last.update!(last_error: "refusé (401)")

    get edit_settings_integration_path("demo_multi")
    assert_select "#integration-connections" do
      assert_equal %w[one.example two.example], css_select(".list-divider").map { |divider| divider.text.strip }
      assert_select ".integration-connection", 3
      assert_select ".integration-connection[data-id='#{integration.connections.first.id}']", text: /team-alpha.*2 éléments.*synchronisée/m
      assert_select ".integration-connection[data-id='#{integration.connections.last.id}'] .connection-state", text: "Échec"
      assert_select "a.add-connection[href=?]", new_settings_integration_connection_path("demo_multi")
    end
    assert_select "button.test-connection", 0
    assert_not_includes response.body, "secret-token"
  end

  test "without a connection: an empty state with the add button" do
    enable_demo_multi
    get edit_settings_integration_path("demo_multi")
    assert_select "#integration-connections .empty-state", text: /Aucune connexion/
    assert_select "#integration-connections .empty-state a.add-connection"
  end

  test "adding a connection logs it and starts a synchronization" do
    enable_demo_multi
    get new_settings_integration_connection_path("demo_multi")
    assert_select "input[name='connection[values][url]']"
    assert_select "input[type=password][name='connection[values][token]']"

    assert_difference -> { IntegrationConnection.count } => 1, -> { BackgroundTask.count } => 1 do
      post settings_integration_connections_path("demo_multi"), params: values
    end
    connection = IntegrationConnection.last
    assert_redirected_to edit_settings_integration_path("demo_multi")
    assert_equal [ "https://coolify.example/team-alpha", "new-token" ], [ connection.value(:url), connection.value(:token) ]
    assert_equal "Démo multiple : connexion « Connexion n° #{connection.id} » ajoutée", Activity.of_kind(:integration_connection_added).last.summary
  end

  test "an invalid connection shows the form again" do
    enable_demo_multi
    assert_no_difference -> { IntegrationConnection.count } do
      post settings_integration_connections_path("demo_multi"), params: values(url: "", token: "")
    end
    assert_response :unprocessable_entity
    assert_select "#error_explanation", text: /URL : obligatoire/
  end

  test "editing keeps the token when left empty, never shows it" do
    connection = enable_demo_multi("https://a.example").connections.first
    get edit_settings_integration_connection_path("demo_multi", connection)
    assert_select "input[name='connection[values][url]'][value='https://a.example']"
    assert_select "input[name='connection[values][token]']:not([value])"
    assert_not_includes response.body, "secret-token"

    patch settings_integration_connection_path("demo_multi", connection), params: { connection: { name: "Prod", values: { url: "https://b.example", token: "" } } }
    assert_redirected_to edit_settings_integration_path("demo_multi")
    connection.reload
    assert_equal [ "Prod", "https://b.example", "secret-token" ], [ connection.name, connection.value(:url), connection.value(:token) ]
  end

  test "testing a new or a saved connection, without saving" do
    connection = enable_demo_multi("https://a.example").connections.first
    post test_settings_integration_connections_path("demo_multi"), params: values, as: :turbo_stream
    assert_select "turbo-stream[target=integration-test-result] .integration-test-result[data-result=good]", text: /équipe team-alpha/
    assert_equal 1, IntegrationConnection.count

    patch test_settings_integration_connection_path("demo_multi", connection), params: values(url: "https://bad.example", token: ""), as: :turbo_stream
    assert_select ".integration-test-result[data-result=crit]", text: /hôte injoignable/
    assert_equal "https://a.example", connection.reload.value(:url)

    post test_settings_integration_connections_path("demo_multi"), params: values
    assert_select ".integration-test-result[data-result=good]"
  end

  test "deleting a connection removes it and logs it" do
    connection = enable_demo_multi("https://a.example").connections.first
    delete settings_integration_connection_path("demo_multi", connection)
    assert_redirected_to edit_settings_integration_path("demo_multi")
    assert_not IntegrationConnection.exists?(connection.id)
    assert_equal 1, Activity.of_kind(:integration_connection_removed).count
  end
end
