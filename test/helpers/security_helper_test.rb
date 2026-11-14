require "test_helper"

class SecurityHelperTest < ActionView::TestCase
  include StubHelpers

  attr_accessor :admin

  def can?(_permission) = admin

  setup do
    self.admin = true
    request.host = "elio.lan"
  end

  def production(&block) = stub_method(Rails.env, :production?, true, &block)

  test "production reached over plain HTTP, on another host than localhost" do
    production { assert SecurityHelper.plain_http?(request) }
  end

  test "not plain HTTP outside production, over HTTPS (forced or told by the proxy), or on localhost" do
    assert_not SecurityHelper.plain_http?(request)
    production do
      request.headers["X-Forwarded-Proto"] = "https"
      assert_not SecurityHelper.plain_http?(request)
      request.headers["X-Forwarded-Proto"] = nil

      request.host = "localhost"
      assert_not SecurityHelper.plain_http?(request)
    end
  end

  test "the notice is for administrators, until they hide it" do
    stub_method(SecurityHelper, :plain_http?, true) do
      assert plain_http_notice?
      self.admin = false
      assert_not plain_http_notice?
      self.admin = true
      cookies[SecurityHelper::PLAIN_HTTP_DISMISSED] = "1"
      assert_not plain_http_notice?
    end
  end
end
