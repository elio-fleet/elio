require "test_helper"

class DesignControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "requires authentication" do
    get design_path
    assert_redirected_to new_user_session_path
  end

  test "shows the interface components" do
    sign_in users(:viewer)
    get design_path

    assert_response :success
    %w[design-header design-buttons design-badges design-tabs design-stats design-filters design-panel design-attention design-status
       design-timeline design-empty design-gauges design-table design-form].each { |id| assert_select "##{id}" }
    assert_select "#design-stats a.stat-tile", 4
    assert_select "#design-stats a.stat-tile[aria-current=true]", 1
    assert_select "header.page-header h1", "Design system"
    assert_select "header.page-header details.actions-menu [role=menuitem]", 3
    assert_select "#design-form[data-controller=dirty-form] .save-bar[hidden]"
    assert_select "h1", 1
    assert_select "#design-table .meter", 4
  end

  test "the layout has the sidebar, the theme switch and a mobile menu button" do
    sign_in users(:one)
    get design_path

    assert_select "body[data-controller~=sidebar] aside.sidebar[data-sidebar-target=panel]"
    assert_select "aside.sidebar button.theme-toggle[data-controller=theme][data-action='theme#toggle']"
    assert_select "header button[data-action='sidebar#open']"
    assert_select "head script", text: /elio-theme/
    assert_select "aside.sidebar form[action=?] button[title=Déconnexion]", destroy_user_session_path
  end
end
