# A package installed on a server (see Inventory::Collectors::Packages):
# dpkg package, snap or Docker image, with the update available if any and,
# for dpkg, the repository it comes from (`origin`: "Debian/bookworm-security",
# "Docker/bookworm", LOCAL_ORIGIN when no repository provides it).
class Inventory::Package < ApplicationRecord
  MANAGERS = %w[dpkg snap docker].freeze
  LOCAL_ORIGIN = "local".freeze
  # Origins (Release "Origin" field) of the distributions themselves: the
  # rest is third-party ("Debian Backports" is told apart by its suite).
  DISTRIBUTION_ORIGINS = /\A(Debian|Ubuntu|Raspbian)/
  BACKPORTS = /-backports\z/
  ORIGIN_KINDS = %w[distribution backports third_party local].freeze

  belongs_to :server

  scope :upgradable, -> { where.not(available_version: nil) }
  scope :security, -> { where(security: true) }
  scope :search, ->(query) { where("inventory_packages.name ILIKE ?", "%#{sanitize_sql_like(query.to_s.strip)}%") }
  # Backports, third-party repositories and packages no repository provides
  # (the SQL twin of origin_kind).
  scope :outside_distribution, -> {
    where.not(origin: nil).where("inventory_packages.origin !~ '^(Debian|Ubuntu|Raspbian)' OR inventory_packages.origin ~ '-backports$'")
  }

  def manager_label = self.class.manager_label(manager)

  def self.manager_label(manager) = I18n.t("inventory.package.managers.#{manager}", default: manager.to_s)

  def upgradable? = available_version.present?

  def self.origin_kind(origin)
    if origin.blank? then nil
    elsif origin == LOCAL_ORIGIN then "local"
    elsif origin.match?(BACKPORTS) then "backports"
    elsif origin.match?(DISTRIBUTION_ORIGINS) then "distribution"
    else "third_party"
    end
  end

  def origin_kind = self.class.origin_kind(origin)

  # "Docker/bookworm", or "Not from a repository" for a local package.
  def origin_label
    origin == LOCAL_ORIGIN ? I18n.t("inventory.package.origins.local") : origin
  end
end
