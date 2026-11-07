require "test_helper"

# The renamed pages answer at their new address; the former one redirects, with its query.
class MovedPagesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "the former addresses redirect to the new ones" do
    sign_in users(:one)
    { "/keys" => "/ssh-keys", "/keys/new" => "/ssh-keys/new", "/keys?kind=outside" => "/ssh-keys?kind=outside",
      "/packages?q=openssl" => "/updates?q=openssl", "/activities?kind=key_added" => "/journal?kind=key_added",
      "/tasks" => "/journal/runs", "/tasks/12" => "/journal/runs/12", "/ovh?tab=ips" => "/hosting?tab=ips" }.each do |from, to|
      get from
      assert_response :moved_permanently
      assert_equal "http://www.example.com#{to}", response.location, from
    end
  end

  test "the new addresses" do
    assert_equal "/ssh-keys", public_keys_path
    assert_equal "/updates", packages_path
    assert_equal "/journal", activities_path
    assert_equal "/journal/runs", tasks_path
    assert_equal "/hosting", ovh_path
  end
end
