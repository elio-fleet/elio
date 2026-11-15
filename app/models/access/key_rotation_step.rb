# Result of a KeyRotation on one server; `phase` tells where it failed
# (install, verify or cleanup).
class KeyRotationStep < ApplicationRecord
  PHASES = %w[install verify cleanup].freeze

  belongs_to :key_rotation, touch: true
  belongs_to :server, optional: true

  enum :status, { rotated: "rotated", failed: "failed" }, validate: true

  def phase_label = I18n.t("key_rotation_step.phases.#{phase}", default: phase.to_s)
end
