# A key outside the keyring that the team knowingly accepts on the servers
# (a provider's support key, a former colleague's key kept for a while…),
# with the reason. It is no longer counted or reported as unknown
# (KeyInsights.known_fingerprints) and the reason shows wherever it is seen.
class ToleratedKey < ApplicationRecord
  belongs_to :user, optional: true

  normalizes :reason, with: ->(value) { value.squish }
  normalizes :name, with: ->(value) { value.squish.presence }

  validates :fingerprint, presence: true, uniqueness: true
  validates :reason, presence: true, length: { maximum: 500 }

  def author_name = user&.email || I18n.t("activity.system")
end
