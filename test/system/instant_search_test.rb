require "application_system_test_case"

# Instant search reloads only the results: what is typed while a request runs
# is kept, and the search field keeps its focus.
class InstantSearchTest < ApplicationSystemTestCase
  include Devise::Test::IntegrationHelpers

  setup { sign_in users(:one) }

  test "the fleet search keeps the focus and every character typed" do
    visit servers_path
    field = find("input.fleet-search")
    field.send_keys("w")
    # The first request (debounced 300 ms) runs, then the user goes on typing.
    assert_current_path(/q=w(&|\z)/)
    assert_no_selector "#fleet-results[busy]"
    field.send_keys("eb")

    assert_field "q", with: "web"
    assert_equal "q", evaluate_script("document.activeElement.name")
    within("#fleet-results #servers") { assert_text servers(:web).name }
    assert_current_path(/q=web/)
  end

  test "a filter of the fleet updates the results and the address" do
    visit servers_path
    find("input.fleet-search").send_keys(servers(:web).name)
    assert_current_path(/q=#{servers(:web).name}/)
    assert_no_selector "#fleet-results[busy]"
    within("#fleet-results") { assert_selector "#servers tbody tr", count: 1 }
    # Links inside the results still open their page.
    within("#fleet-results #servers") { click_on servers(:web).name }
    assert_selector "h1", text: servers(:web).name, wait: 10
  end

  test "the ports search keeps the field" do
    visit ports_path
    field = find("input[name=q]")
    field.send_keys("2")
    sleep 0.6
    field.send_keys("2")
    assert_field "q", with: "22"
    assert_equal "q", evaluate_script("document.activeElement.name")
  end
end
