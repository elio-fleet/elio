# Base class of the inventory collectors. A collector gathers one category
# (os, health, packages…) through an open Ssh::Connection, with read-only
# commands, and turns their output into plain data (pure parsing, testable on
# recorded outputs):
#
#   class Inventory::Collectors::Os < Inventory::Collector
#     def collect = ok(self.class.parse(run("cat /etc/os-release").stdout))
#     def self.parse(output) = …
#   end
#
# Subclasses may also define `self.changes(previous_data, data)`, returning
# the activities to log when the data changed between two collections
# (`[{ kind: :os_upgraded, data: { … } }]`).
class Inventory::Collector
  Outcome = Data.define(:status, :data, :message)

  # Raised by a collector that cannot do its job; its message is shown in the UI.
  class Error < StandardError; end

  # Categories in collection order, with their collector class name.
  CATEGORIES = { "os" => "Inventory::Collectors::Os", "health" => "Inventory::Collectors::Health",
                 "packages" => "Inventory::Collectors::Packages", "services" => "Inventory::Collectors::Services",
                 "ports" => "Inventory::Collectors::Ports", "network" => "Inventory::Collectors::Network",
                 "scheduled_tasks" => "Inventory::Collectors::ScheduledTasks",
                 # Last: a scan that times out ends the SSH session.
                 "docker" => "Inventory::Collectors::Docker" }.freeze

  MAX_OUTPUT = 8.megabytes

  class << self
    attr_writer :registry

    # category => collector class name, overridable in tests.
    def registry = @registry ||= CATEGORIES.dup

    def categories = registry.keys

    def label_for(category) = I18n.t("inventory.categories.#{category}", default: category.to_s.humanize)

    def for(category) = registry.fetch(category.to_s).to_s.constantize

    def changes(_previous_data, _data) = []

    # Summary columns of the server to update from the collected data.
    def server_attributes(_data) = {}

    # Extra records to keep for each successful collection (e.g. history).
    def record(_server, _data, _at) = nil

    # Part of the data kept in the snapshot (big lists can go elsewhere).
    def snapshot_data(data) = data

    # Output of the scripts of config/ssh_commands.yml, cut on its
    # "@@elio <name>" lines: { name => body }, "" for a missing section.
    def sections(output)
      output.to_s.split(/^@@elio (\S+)\n/).drop(1).each_slice(2).to_h { |name, body| [ name, body.to_s ] }.tap { |sections| sections.default = "" }
    end
  end

  attr_reader :ssh, :previous

  # `previous`: data of the last successful collection of this category (or nil).
  def initialize(ssh, previous: nil)
    @ssh = ssh
    @previous = previous
  end

  def collect
    raise NotImplementedError
  end

  private

  # Runs a read-only command, through `sudo -n` when `privileged` and root is
  # available. Raises Error when the output is unreasonably large.
  # Runs a command of config/ssh_commands.yml ("inventory.health"…), through
  # sudo when it needs root (see Ssh::Connection#run_command).
  def run(key, **values)
    ssh.run_command(key, **values).tap do |result|
      raise Error, I18n.t("inventory.collector.output_too_large", key: key) if result.stdout.bytesize > MAX_OUTPUT
    end
  end

  def privileged? = ssh.privileged?

  # Reason of a Docker command that failed. The account may not read the
  # Docker socket (neither root nor in the docker group): one common reason,
  # so Packages, Services and Docker show the same cause instead of three
  # copies of Docker's error. `otherwise`: the reason of any other failure.
  def docker_failure(error, otherwise)
    error.to_s.match?(/denied/i) ? I18n.t("inventory.collector.no_docker_access") : otherwise
  end

  def ok(data, message: nil) = Outcome.new(status: "ok", data: data, message: message)

  # Collected, but some details need root access that Elio does not have.
  def partial(data, message) = Outcome.new(status: "partial", data: data, message: message)

  def unsupported(message) = Outcome.new(status: "unsupported", data: {}, message: message)
end
