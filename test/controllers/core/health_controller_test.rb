require "test_helper"

class HealthControllerTest < ActionDispatch::IntegrationTest
  include StubHelpers

  TOKEN = "a-long-health-token"

  setup { Throttled::STORE.clear }
  teardown { Throttled::STORE.clear }

  test "without credentials: 200 without a query, a cookie, nor the version" do
    queries = count_queries { get "/up" }

    assert_response :ok
    assert_equal 0, queries
    assert_nil response.headers["Set-Cookie"]
    assert_no_match Elio::VERSION, response.body
  end

  test "HEAD answers without a body" do
    head "/up"
    assert_response :ok
    assert_empty response.body
  end

  test "with the token: the detailed health in JSON, never cached" do
    with_health(workers: true, automations: 1.minute.ago) { get "/up", headers: bearer(TOKEN) }

    assert_response :ok
    assert_equal "no-store", response.headers["Cache-Control"]
    assert_nil response.headers["Set-Cookie"]
    body = response.parsed_body
    assert_equal [ "ok", Elio::VERSION ], body.values_at("status", "version")
    assert_equal %w[ok ok ok], body["checks"].values_at("database", "jobs", "automations").pluck("status")
  end

  test "a stopped worker or automations late make it 503" do
    with_health(workers: false, automations: 1.minute.ago) { get "/up", headers: bearer(TOKEN) }
    assert_response :service_unavailable
    assert_equal [ "down", "down" ], [ response.parsed_body["status"], response.parsed_body.dig("checks", "jobs", "status") ]

    with_health(workers: true, automations: 10.minutes.ago) { get "/up", headers: bearer(TOKEN) }
    assert_response :service_unavailable
    assert_equal "late", response.parsed_body.dig("checks", "automations", "status")
  end

  test "a wrong token, or no ELIO_HEALTH_TOKEN set, gets a bare 401" do
    with_health(workers: true, automations: 1.minute.ago) { get "/up", headers: bearer("wrong") }
    assert_response :unauthorized
    assert_empty response.body

    with_env("ELIO_HEALTH_TOKEN" => nil) { get "/up", headers: bearer("") }
    assert_response :unauthorized
    assert_empty response.body
  end

  test "guessing the token is rate-limited, the plain health check is not" do
    with_env("ELIO_HEALTH_TOKEN" => TOKEN) do
      20.times { get "/up", headers: bearer("wrong") }
      get "/up", headers: bearer(TOKEN)
      assert_response :too_many_requests
    end

    25.times { get "/up" }
    assert_response :ok
  end

  private

  def bearer(token) = { "Authorization" => "Bearer #{token}" }

  def with_health(workers:, automations:, &block)
    with_env("ELIO_HEALTH_TOKEN" => TOKEN) do
      stub_method(JobWorkers, :running?, workers) do
        stub_method(JobWorkers, :last_finished_at, automations, &block)
      end
    end
  end

  def count_queries(&block)
    ActiveRecord::Base.connection.clear_query_cache
    count = 0
    counter = ->(*, payload) { count += 1 unless payload[:name].in?(%w[SCHEMA TRANSACTION]) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end

  def with_env(values)
    previous = values.keys.to_h { |key| [ key, ENV[key] ] }
    values.each { |key, value| ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| ENV[key] = value }
  end
end
