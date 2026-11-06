require "application_system_test_case"

class DnsSearchTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  test "⌘K finds who has a DNS name" do
    Integration.create!(kind: "technitium", enabled: true, settings: { "url" => "https://d.test" }, secrets: { "api_token" => "t" })
    Dns::Store.replace("technitium", [ { zone: "example.test", name: "web.example.test", record_type: "A", value: "198.51.100.1" } ])
    sign_in users(:viewer)
    visit root_path
    find("body").send_keys([ :control, "k" ])
    find("dialog[open] input").send_keys("web.example.test")
    find("dialog[open] [role=option]", text: "Qui a le nom DNS « web.example.test » ?").click
    assert_selector "tr.dns-record[data-name='web.example.test']"
  end
end
