# A named set of servers (e.g. "Production", "Clients"), used to filter the
# server list and to select several servers at once.
class ServerGroup < ApplicationRecord
  # Badge classes are written out in full so Tailwind generates them.
  COLORS = {
    "slate" => [ "bg-slate-100 text-slate-700 ring-slate-500/20 dark:bg-slate-800/60 dark:text-slate-300 dark:ring-slate-400/30", "bg-slate-400" ],
    "red" => [ "bg-red-50 text-red-700 ring-red-600/20 dark:bg-red-950/60 dark:text-red-300 dark:ring-red-400/30", "bg-red-500" ],
    "amber" => [ "bg-amber-50 text-amber-800 ring-amber-600/20 dark:bg-amber-950/60 dark:text-amber-300 dark:ring-amber-400/30", "bg-amber-500" ],
    "emerald" => [ "bg-emerald-50 text-emerald-700 ring-emerald-600/20 dark:bg-emerald-950/60 dark:text-emerald-300 dark:ring-emerald-400/30", "bg-emerald-500" ],
    "sky" => [ "bg-sky-50 text-sky-700 ring-sky-600/20 dark:bg-sky-950/60 dark:text-sky-300 dark:ring-sky-400/30", "bg-sky-500" ],
    "indigo" => [ "bg-indigo-50 text-indigo-700 ring-indigo-600/20 dark:bg-indigo-950/60 dark:text-indigo-300 dark:ring-indigo-400/30", "bg-indigo-500" ],
    "violet" => [ "bg-violet-50 text-violet-700 ring-violet-600/20 dark:bg-violet-950/60 dark:text-violet-300 dark:ring-violet-400/30", "bg-violet-500" ],
    "pink" => [ "bg-pink-50 text-pink-700 ring-pink-600/20 dark:bg-pink-950/60 dark:text-pink-300 dark:ring-pink-400/30", "bg-pink-500" ]
  }.freeze

  has_many :memberships, class_name: "ServerGroupMembership", dependent: :delete_all
  has_many :servers, -> { order(:name) }, through: :memberships

  normalizes :name, with: ->(value) { value.squish }
  normalizes :expected_ports, with: ->(value) { value.squish.presence }

  validates :name, presence: true, uniqueness: { case_sensitive: false }, length: { maximum: 50 }
  validates :color, inclusion: { in: COLORS.keys }
  validate :expected_ports_must_be_valid

  # The SSH sources chosen for the group (none = the whole list, SshSource).
  def ssh_sources = SshSource.where(id: ssh_source_ids).ordered

  # Only sources that exist: an unknown id would make a group "restrict" SSH
  # to nothing, and its servers fall back to the whole list.
  def ssh_source_ids=(ids)
    wanted = Array(ids).compact_blank.map(&:to_i).uniq
    super(wanted.empty? ? [] : SshSource.where(id: wanted).pluck(:id).sort_by { |id| wanted.index(id) })
  end

  def badge_classes = COLORS.dig(color, 0)
  def dot_classes = COLORS.dig(color, 1)

  def self.color_label(color) = I18n.t("server_group.colors.#{color}")

  # Ports the servers of the group are expected to expose publicly (none = no check).
  def expected_port_list = expected_ports.present? ? Inventory::PortList.new(expected_ports) : nil

  private

  def expected_ports_must_be_valid
    invalid = Inventory::PortList.new(expected_ports).invalid
    errors.add(:expected_ports, :invalid_ports, ports: invalid.join(", ")) if invalid.any?
  end
end
