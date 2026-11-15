# Badges of the state of an SSH key: weak (AuthorizedKey or PublicKey), and
# the expiry date of a keyring key.
module KeysHelper
  # Warning badge of a weak key, its reason in the title; nil otherwise.
  def weak_key_badge(key)
    return unless key&.weak?

    status_badge(:warn, t("public_key.weakness.badge"), class: "key-weak", title: weak_key_reason(key))
  end

  # Why the key is weak and what to do, in one sentence.
  def weak_key_reason(key) = t("public_key.weakness.#{key.weakness}", bits: key.rsa_bits)

  # Expired (critical) or expiring soon (warning) badge of a keyring key; nil otherwise.
  def public_key_expiry_badge(public_key)
    date = public_key.expires_on && l(public_key.expires_on, format: :long)
    if public_key.expired?
      status_badge(:crit, t("public_key.expiry.expired"), class: "key-expiry-date", title: date)
    elsif public_key.expiring_soon?
      status_badge(:warn, t("public_key.expiry.expires_on", date: l(public_key.expires_on, format: :short)), class: "key-expiry-date", title: date)
    end
  end
end
