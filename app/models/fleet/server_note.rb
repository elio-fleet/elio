# A note left on a server by a user (any role), written in Markdown and shown
# on the server's Notes tab. Rendered to HTML then sanitized (Markdown#html):
# no raw HTML, no images, links open without a referrer.
class ServerNote < ApplicationRecord
  MAX_LENGTH = 10_000

  belongs_to :server
  belongs_to :user, optional: true

  normalizes :body, with: ->(body) { body.to_s.strip }
  validates :body, presence: true, length: { maximum: MAX_LENGTH }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def html = Markdown.html(body)

  # Plain text, one line (activities, notifications).
  def excerpt(length = 120) = Markdown.text(body).squish.truncate(length)

  def editable_by?(viewer) = viewer.present? && user_id == viewer.id

  def deletable_by?(viewer) = editable_by?(viewer) || viewer&.role == "admin"

  def edited? = updated_at != created_at

  def author_name = user&.email || I18n.t("server_notes.deleted_user")
end
