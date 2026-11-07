require "date"

module Elio
  # Assembles the fragments of changelog.d/ (one per pull request) into a
  # version's section of CHANGELOG.md, so that pull requests never edit the
  # same lines. See changelog.d/README.md.
  class Changelog
    HEADINGS = %w[Upgrading Added Changed Fixed Security Removed].freeze
    REPOSITORY = "https://github.com/elio-fleet/elio".freeze

    class Error < StandardError; end

    def initialize(root)
      @root = root
      @dir = File.join(root, "changelog.d")
      @path = File.join(root, "CHANGELOG.md")
    end

    def fragments = Dir[File.join(@dir, "*.md")].reject { |file| File.basename(file) == "README.md" }.sort

    # { "Added" => ["- …"], … } from every fragment; raises on a malformed one.
    def entries
      fragments.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |file, all|
        heading = nil
        File.readlines(file, chomp: true).each_with_index do |line, index|
          next if line.strip.empty?

          if (match = line.match(/\A### (\w+)\s*\z/))
            heading = match[1]
            raise Error, "#{File.basename(file)}:#{index + 1}: unknown heading “#{heading}” (#{HEADINGS.join(", ")})" unless HEADINGS.include?(heading)
          elsif line.start_with?("- ", "  ")
            raise Error, "#{File.basename(file)}:#{index + 1}: an entry before any heading" unless heading

            line.start_with?("  ") ? all[heading][-1] += "\n#{line}" : all[heading] << line
          else
            raise Error, "#{File.basename(file)}:#{index + 1}: expected “### Heading” or “- entry”"
          end
        end
        raise Error, "#{File.basename(file)}: empty fragment" if heading.nil?
      end
    end

    def previous_version = File.read(@path)[/^## \[(\d[^\]]*)\]/, 1]

    # The Markdown of the section (without its "## [version]" line).
    def section(previous: previous_version)
      HEADINGS.filter_map do |heading|
        lines = entries[heading]
        next if lines.empty?

        title = heading == "Upgrading" && previous ? "Upgrading from #{previous}" : heading
        "### #{title}\n\n#{lines.join("\n")}\n"
      end.join("\n")
    end

    # Writes the section of `version` under [Unreleased], updates the
    # comparison links and deletes the fragments.
    def release!(version, date: Date.today)
      raise Error, "no fragment in changelog.d/" if fragments.empty?

      text = File.read(@path)
      raise Error, "CHANGELOG.md already has a section #{version}" if text.include?("## [#{version}]")

      previous = previous_version
      body = section(previous: previous)
      text = text.sub("## [Unreleased]\n", "## [Unreleased]\n\n## [#{version}] — #{date.iso8601}\n\n#{body}")
      text = text.gsub(/\n{3,}/, "\n\n")
      text = text.sub(%r{^\[Unreleased\]: .*$}, "[Unreleased]: #{REPOSITORY}/compare/v#{version}...HEAD\n[#{version}]: #{REPOSITORY}/compare/v#{previous}...v#{version}")
      File.write(@path, text)
      fragments.each { |file| File.delete(file) }
      body
    end
  end
end
