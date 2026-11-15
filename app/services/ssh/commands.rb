require "shellwords"

# The commands Elio runs on the servers, loaded from config/ssh_commands.yml
# (the only place they are written). A command is found by "role.name"
# ("inventory.health", "keys.append"), its variant picked for the server's
# distribution family, its @{values} shell-escaped, and multi-line scripts
# wrapped in `sh -c`. Ssh::Connection#run_command runs them.
module Ssh::Commands
  FILE = Rails.root.join("config/ssh_commands.yml")
  DEFAULT_TIMEOUT = 60
  PLACEHOLDER = /@\{(\w+)\}/
  OPTIONS = %w[description writes run_as timeout shell].freeze

  class UnknownCommand < StandardError; end
  class MissingValue < StandardError; end

  Command = Data.define(:key, :description, :writes, :run_as, :timeout, :shell, :variants) do
    def root? = run_as == "root"
    def writes? = writes == true
    def distro_specific? = variants.keys != [ "default" ]
    def role = key.split(".", 2).first

    # Name of the variant for a distribution: its ID, then each ID_LIKE, then default.
    def variant(distros = []) = distros.map(&:to_s).find { |distro| variants.key?(distro) } || "default"

    def template(distros = [])
      variants.fetch(variant(distros)) { raise UnknownCommand, "#{key}: no variant for #{distros.inspect}" }
    end

    # The command line to send: values escaped, scripts wrapped in `sh -c`.
    def render(distros: [], **values)
      text = template(distros).gsub(PLACEHOLDER) do
        name = Regexp.last_match(1).to_sym
        raise MissingValue, "#{key}: missing value @{#{name}}" unless values.key?(name)

        Shellwords.escape(values.fetch(name).to_s)
      end
      shell ? "sh -c #{Shellwords.escape(text)}" : text.strip
    end
  end

  class << self
    def fetch(key)
      all.fetch(key.to_s) { raise UnknownCommand, "Unknown SSH command #{key} (see config/ssh_commands.yml)" }
    end

    def render(key, distros: [], **values) = fetch(key).render(distros: distros, **values)

    # { "role.name" => Command }, read once (again after a change in
    # development), plus the commands registered by the tests (`extra`).
    def all
      @all = nil if Rails.env.development? && @loaded_at && FILE.mtime > @loaded_at
      @all ||= begin
        @loaded_at = Time.current
        build_all(YAML.safe_load_file(FILE))
      end
      @extra ? @all.merge(@extra) : @all
    end

    # Test only: commands of fake collectors, same format as the file
    # ({ "role" => { "name" => { "default" => "…" } } }), nil to remove them.
    def extra=(definitions)
      @extra = definitions && build_all(definitions.deep_stringify_keys)
    end

    # "ubuntu debian" (output of connection.os_release) → ["ubuntu", "debian"].
    def parse_distros(output) = output.to_s.split.map(&:downcase).uniq

    def reload! = @all = nil

    private

    def build_all(definitions)
      definitions.flat_map do |role, commands|
        commands.map do |name, spec|
          key = "#{role}.#{name}"
          variants = spec.except(*OPTIONS)
          raise UnknownCommand, "#{key}: no default variant" unless variants.key?("default")

          [ key, Command.new(key: key, description: spec.fetch("description", ""), writes: spec["writes"] == true, run_as: spec.fetch("run_as", "user"),
                             timeout: spec.fetch("timeout", DEFAULT_TIMEOUT), shell: spec["shell"] == true, variants: variants.transform_values(&:to_s).freeze) ]
        end
      end.to_h.freeze
    end
  end
end
