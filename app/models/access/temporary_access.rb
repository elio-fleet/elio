# A key authorized on a server account for a limited time. The authorized_keys
# line carries an OpenSSH `expiry-time` option, so sshd refuses the key once
# expired even if the app is down; ExpireTemporaryAccessJob then removes the
# line and ends the access. At most one active access per server, account and key.
# Ended accesses are kept: they are the server's history of temporary accesses.
class TemporaryAccess < ApplicationRecord
  # Choices offered in the UI: param value (minutes) => duration.
  DURATIONS = { "10" => 10.minutes, "30" => 30.minutes, "60" => 1.hour, "240" => 4.hours, "1440" => 1.day, "10080" => 7.days }.freeze

  # A key_expiring activity is recorded this long before the end, once, for
  # accesses long enough for a reminder to make sense.
  REMINDER_LEAD = 10.minutes
  REMINDER_MIN_LENGTH = 30.minutes

  belongs_to :server
  belongs_to :public_key, optional: true

  validates :unix_user, :key_blob, :fingerprint, :expires_at, presence: true

  scope :active, -> { where(ended_at: nil) }
  scope :expired, -> { active.where(expires_at: ..Time.current) }
  scope :ended, -> { where.not(ended_at: nil) }
  scope :due_for_reminder, lambda {
    active.where(expiry_reminded_at: nil, expires_at: Time.current..REMINDER_LEAD.from_now)
          .where("expires_at - created_at > make_interval(secs => ?)", REMINDER_MIN_LENGTH.to_i)
  }

  def self.duration_for(param)
    DURATIONS.fetch(param.to_s) { raise ArgumentError, "Unknown duration: #{param.inspect}" }
  end

  # "10 minutes", "1 hour", "7 days" in the reader's language.
  def self.label_for(duration)
    seconds = duration.to_i
    unit, size = [ [ :days, 86_400 ], [ :hours, 3600 ], [ :minutes, 60 ] ].find { |_, size| (seconds % size).zero? && seconds >= size } || [ :minutes, 60 ]
    I18n.t("duration.#{unit}", count: seconds / size)
  end

  # [label, value] of the duration select.
  def self.options = DURATIONS.map { |value, duration| [ label_for(duration), value ] }

  def account = AuthorizedKeysAccount.for(server, unix_user) || AuthorizedKeysAccount.login(server)

  def active? = ended_at.nil?

  def expired? = expires_at <= Time.current

  def end!
    update!(ended_at: Time.current) if active?
  end

  # Ended by its expiry (rather than removed or replaced before it).
  def expired_at_term? = ended_at.present? && ended_at >= expires_at

  # Records the key_expiring activity, once (several workers may run the reminder at once).
  def remind!
    return unless self.class.where(id: id, expiry_reminded_at: nil).update_all(expiry_reminded_at: Time.current) == 1

    Activity.record!(:key_expiring, server: server, public_key: public_key, unix_user: unix_user, user: nil,
                                    fingerprint: fingerprint, expires_at: expires_at.iso8601)
  end
end
