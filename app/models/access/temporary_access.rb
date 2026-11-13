# A key authorized on a server account for a limited time. The authorized_keys
# line carries an OpenSSH `expiry-time` option, so sshd refuses the key once
# expired even if the app is down; ExpireTemporaryAccessJob then removes the
# line and ends the access. At most one active access per server, account and key.
class TemporaryAccess < ApplicationRecord
  # Choices offered in the UI: param value (minutes) => duration.
  DURATIONS = { "10" => 10.minutes, "30" => 30.minutes, "60" => 1.hour, "240" => 4.hours, "1440" => 1.day, "10080" => 7.days }.freeze

  belongs_to :server
  belongs_to :public_key, optional: true

  validates :unix_user, :key_blob, :fingerprint, :expires_at, presence: true

  scope :active, -> { where(ended_at: nil) }
  scope :expired, -> { active.where(expires_at: ..Time.current) }

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
end
