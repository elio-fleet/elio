require "test_helper"

class ToleratedKeysControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def tolerate(reason: "Vendor support")
    post tolerated_keys_path, params: { tolerated_key: { fingerprint: "SHA256:vendor", name: "support@vendor", reason: reason } }
  end

  test "an operator tolerates a key with a reason, logged, then tolerates it no longer" do
    sign_in users(:operator)

    assert_difference "ToleratedKey.count", 1 do
      tolerate
    end
    assert_redirected_to public_keys_path(kind: "outside")
    assert_equal "La clé « support@vendor » est tolérée et n'est plus signalée comme inconnue.", flash[:notice]
    tolerated = ToleratedKey.sole
    assert_equal [ "Vendor support", users(:operator) ], [ tolerated.reason, tolerated.user ]
    activity = Activity.of_kind(:key_tolerated).sole
    assert_equal [ "support@vendor", "SHA256:vendor", "Vendor support", users(:operator) ], [ activity.key_name, activity.data["fingerprint"], activity.data["reason"], activity.user ]

    delete tolerated_key_path(tolerated)
    assert_redirected_to public_keys_path(kind: "outside")
    assert_not ToleratedKey.exists?
    assert_equal "SHA256:vendor", Activity.of_kind(:key_tolerance_removed).sole.data["fingerprint"]
  end

  test "a reason is required" do
    sign_in users(:operator)

    assert_no_difference "ToleratedKey.count" do
      tolerate(reason: " ")
    end
    assert_redirected_to public_keys_path(kind: "outside")
    assert_match "La raison", flash[:alert]
  end

  test "a viewer cannot tolerate a key" do
    sign_in users(:viewer)

    assert_no_difference "ToleratedKey.count" do
      tolerate
    end
  end
end
