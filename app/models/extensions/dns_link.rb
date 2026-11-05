# A DNS name attached by hand to a server (or, server nil, to none), for
# every record of that name whatever its source. Kept across synchronizations.
class DnsLink < ApplicationRecord
  belongs_to :server, optional: true
  belongs_to :user, optional: true

  normalizes :name, with: ->(name) { name.to_s.strip.downcase.chomp(".") }
  validates :name, presence: true, uniqueness: true
end
