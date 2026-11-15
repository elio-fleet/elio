# Health thresholds of a server or a group of servers, on top of those of the
# settings (Inventory::HealthThresholds says which one applies). Only the
# thresholds set are stored: a blank field keeps the one inherited.
module HealthThresholdOverrides
  extend ActiveSupport::Concern

  included do
    validate :health_thresholds_valid
  end

  def health_thresholds=(values)
    super(Inventory::HealthThresholds.clean(values))
  end

  private

  def health_thresholds_valid
    Inventory::HealthThresholds.errors(health_thresholds.to_h).each { |error| errors.add(:health_thresholds, error) }
  end
end
