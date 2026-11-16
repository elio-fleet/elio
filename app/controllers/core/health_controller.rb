# GET /up, public: the health check of Docker, a proxy or a load balancer.
# Without credentials it stays Rails' own: 200 as soon as the application
# runs, without a database query, a session or a cookie.
#
# With "Authorization: Bearer <ELIO_HEALTH_TOKEN>", it answers the detailed
# health of Installation::Health in JSON (503 when something is down), for a
# supervision tool such as Uptime Kuma. A wrong token, or no ELIO_HEALTH_TOKEN
# set, gets a bare 401: the details are never shown without the token. The
# path stays /up so that it keeps the exceptions of the health check (no host
# check, no SSL redirect, silent in the logs).
class HealthController < Rails::HealthController
  # Guessing the token: a few tries per minute and per IP. Only requests with
  # credentials count, so the Docker health check is never limited.
  rate_limit to: 20, within: 1.minute, store: Throttled::STORE, name: "health_details",
             if: -> { request.authorization.present? }, with: -> { head :too_many_requests }

  def show
    return super if request.authorization.blank?
    return head(:unauthorized) unless token_valid?

    health = Installation::Health.new.call
    response.headers["Cache-Control"] = "no-store"
    render json: health, status: health[:status] == "ok" ? :ok : :service_unavailable
  end

  private

  def token_valid?
    expected = ENV["ELIO_HEALTH_TOKEN"].to_s
    return false if expected.empty?

    authenticate_with_http_token { |token, _options| ActiveSupport::SecurityUtils.secure_compare(token, expected) } || false
  end
end
