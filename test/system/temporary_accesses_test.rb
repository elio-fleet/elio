require "application_system_test_case"

class TemporaryAccessesSystemTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers
  include StubHelpers
  include TemporaryAccessHelpers

  test "from the expiry of a key on the server, open its temporary accesses and extend one" do
    access = create_temporary_access(expires_at: 20.minutes.from_now)
    create_temporary_access(public_key: public_keys(:alice), unix_user: "root", expires_at: 1.day.ago).tap(&:end!)
    lines = [ ssh_keys(:main).public_key, %(expiry-time="20300101000000Z" #{public_keys(:ci).content}) ]
    stub_method_until_teardown(Keys::AuthorizedKeysReader, :call_all,
                               keys_read(Keys::AuthorizedKeysReader::Result.new(keys: AuthorizedKey.parse(lines.join("\n")), error_title: nil, error_details: nil)))
    stub_method_until_teardown(Keys::AccessExtension, :call, lambda { |record, duration|
      record.update!(expires_at: record.expires_at + duration, extensions_count: record.extensions_count + 1)
      Keys::AccessExtension::Result.new(status: :extended, error_title: nil, error_details: nil)
    })
    sign_in users(:operator)

    visit server_path(servers(:web), tab: "keys")
    find(".key-expiry").click

    assert_selector "h1", text: "Accès temporaires"
    assert_selector ".past-temporary-access", text: "Expiré"
    within("##{ActionView::RecordIdentifier.dom_id(access)}") do
      select "4 heures", from: "Prolonger de"
      click_on "Prolonger"
    end

    assert_selector "#flash", text: "CI sur deploy : prolongé de 4 heures"
    assert_selector "##{ActionView::RecordIdentifier.dom_id(access)}", text: "prolongé une fois"
    assert_in_delta 260.minutes.from_now, access.reload.expires_at, 60
  end
end
