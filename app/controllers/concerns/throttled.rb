# Per-IP rate limits of the public pages (sign in, password reset,
# invitation, first setup, 2FA): Rails' rate_limit, with a store that also
# works where the cache keeps nothing (tests), and a French message.
module Throttled
  extend ActiveSupport::Concern

  STORE = Rails.cache.is_a?(ActiveSupport::Cache::NullStore) ? ActiveSupport::Cache::MemoryStore.new : Rails.cache

  class_methods do
    # `to` requests per IP `within` the period; then back to `redirect` (a
    # route helper name) with a message, 429. `by` counts by something else
    # than the IP (a lambda run in the controller, e.g. the email asked for);
    # `name` keeps two limits of the same action apart.
    def throttle(only:, to:, within:, redirect:, by: nil, name: nil)
      options = { to: to, within: within, only: only, store: STORE,
                  name: [ "#{controller_path}##{Array(only).join(",")}", name ].compact.join(":"),
                  with: -> { redirect_to main_app.public_send(redirect), alert: I18n.t("throttled.too_many"), status: :see_other } }
      options[:by] = by if by
      rate_limit(**options)
    end
  end
end
