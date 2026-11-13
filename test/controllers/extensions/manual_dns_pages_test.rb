require "test_helper"

class ManualDnsPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @integration = Integration.find_or_create_by!(kind: "manual_dns").tap { |integration| integration.update!(enabled: true) }
  end

  test "a source is added from the settings, with its own wording, previewed, then its records are on the DNS page" do
    sign_in users(:one)

    get new_settings_integration_connection_path("manual_dns")
    assert_select "h2", "Nouvelle source DNS"
    assert_select "textarea[name='connection[values][records]']"
    assert_select "label", text: /Nom de la source/

    post test_settings_integration_connections_path("manual_dns"), params: { connection: { name: "Bureau", values: { records: "nas.office.lan,A,10.0.0.5\nx,MX,y" } } }, as: :turbo_stream
    assert_match "Aperçu : 1 enregistrement lu, 1 ligne(s) refusée(s)", response.body
    assert_equal 0, @integration.connections.count

    post settings_integration_connections_path("manual_dns"), params: { connection: { name: "Bureau", values: { records: "nas.office.lan,A,10.0.0.5" } } }
    assert_equal "Source « Bureau » ajoutée.", flash[:notice]
    @integration.connections.sole.sync!

    get dns_records_path
    source = "manual:#{@integration.connections.sole.id}"
    assert_select ".dns-sources li[data-source=?]", source, text: /Bureau/
    get dns_records_path(source: source)
    assert_select "tr.dns-record", 1
    assert_select "tr.dns-record .dns-source", "Bureau"
  end
end
