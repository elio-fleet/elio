# Grants a keyring key access to a server account, permanently or for a limited
# time (see TemporaryAccess), and keeps the temporary accesses in sync:
#
# - a temporary grant records a TemporaryAccess and schedules its expiry;
# - any new grant for a key that has an active temporary access replaces its
#   authorized_keys line (to change or drop the expiry) and ends the old access;
# - a key already authorized permanently stays as it is.
class Keys::AccessGrant
  def self.call(server, public_key, account:, duration: nil, **connection_options)
    active = TemporaryAccess.active.find_by(server: server, unix_user: account.unix_user, fingerprint: public_key.fingerprint)
    expires_at = duration && Time.current + duration

    result = Keys::PublicKeyAuthorization.call(server, public_key, account: account, expires_at: expires_at, replace: active.present?, **connection_options)
    return result unless result.success?

    TemporaryAccess.transaction do
      active&.end!
      schedule_expiry(server, public_key, account, expires_at) if expires_at && result.added?
    end
    log(server, public_key, account, duration, expires_at) if result.added?
    result
  end

  def self.log(server, public_key, account, duration, expires_at)
    Activity.record!(:key_added, server: server, public_key: public_key, unix_user: account.unix_user,
                                 key_name: public_key.authorized_key.comment || public_key.name, fingerprint: public_key.fingerprint,
                                 duration_seconds: duration&.to_i, expires_at: expires_at&.iso8601)
  end
  private_class_method :log

  def self.schedule_expiry(server, public_key, account, expires_at)
    access = TemporaryAccess.create!(server: server, public_key: public_key, unix_user: account.unix_user,
                                     key_blob: public_key.authorized_key.key, fingerprint: public_key.fingerprint, expires_at: expires_at)
    ExpireTemporaryAccessJob.set(wait_until: expires_at).perform_later(access)
  end
  private_class_method :schedule_expiry
end
