# Request-scoped attributes: the signed-in user, recorded as the author of
# activities (nil in jobs and automations, shown as "Système").
class Current < ActiveSupport::CurrentAttributes
  attribute :user
  # The enabled DNS sources (Dns.source_integrations), read once per request.
  attribute :dns_sources
end
