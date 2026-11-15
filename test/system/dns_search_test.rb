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

  test "searching an IP, then attaching every name found to a server at once" do
    Integration.create!(kind: "technitium", enabled: true, settings: { "url" => "https://d.test" }, secrets: { "api_token" => "t" })
    Dns::Store.replace("technitium", [ { zone: "example.test", name: "shop.example.test", record_type: "A", value: "198.51.100.7" },
                                       { zone: "example.test", name: "www.example.test", record_type: "CNAME", value: "shop.example.test" },
                                       { zone: "example.test", name: "other.example.test", record_type: "A", value: "198.51.100.70" } ])
    sign_in users(:operator)
    visit dns_records_path
    fill_in "Nom ou valeur", with: "198.51.100.7"
    assert_selector ".dns-ip-names", text: "2 noms mènent à 198.51.100.7"
    assert_selector "tr.dns-record", count: 2

    within("#dns-records thead") { click_button "Tous" }
    select servers(:backup).name, from: "Rattacher les noms cochés à"
    click_button "Rattacher"
    assert_text "2 noms sont rattachés à « #{servers(:backup).name} »."
    assert_equal [ servers(:backup).id ] * 2, DnsRecord.where(name: %w[shop.example.test www.example.test]).pluck(:server_id)
    assert_nil DnsRecord.find_by!(name: "other.example.test").server_id
  end
end
