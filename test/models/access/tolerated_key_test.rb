require "test_helper"

class ToleratedKeyTest < ActiveSupport::TestCase
  test "needs a fingerprint and a reason, one per fingerprint" do
    tolerated = ToleratedKey.new(fingerprint: "SHA256:abc", name: "  support@vendor ", reason: "  Vendor   support ")

    assert tolerated.save
    assert_equal "Vendor support", tolerated.reason
    assert_equal "support@vendor", tolerated.name

    assert_not ToleratedKey.new(fingerprint: "SHA256:abc", reason: "Again").valid?
    assert_includes ToleratedKey.new(fingerprint: "SHA256:def", reason: " ").tap(&:valid?).errors.attribute_names, :reason
    assert_includes ToleratedKey.new(reason: "Why").tap(&:valid?).errors.attribute_names, :fingerprint
  end

  test "a deleted author leaves the tolerance in place" do
    user = User.create!(email: "temp@example.com", password: "password1234")
    tolerated = ToleratedKey.create!(fingerprint: "SHA256:abc", reason: "Vendor", user: user)

    user.destroy!

    assert_nil tolerated.reload.user
    assert_equal "Système", tolerated.author_name
  end
end
