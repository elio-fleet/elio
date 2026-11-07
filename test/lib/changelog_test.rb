require "test_helper"
require Rails.root.join("lib/elio/changelog")

class ChangelogTest < ActiveSupport::TestCase
  def with_repo(fragments)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "changelog.d"))
      File.write(File.join(dir, "changelog.d", "README.md"), "# how to")
      fragments.each { |name, text| File.write(File.join(dir, "changelog.d", name), text) }
      File.write(File.join(dir, "CHANGELOG.md"), <<~MD)
        # Changelog

        ## [Unreleased]

        ## [0.1.0-beta.4] — 2026-11-06

        ### Added

        - Old.

        [Unreleased]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.4...HEAD
        [0.1.0-beta.4]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.3.1...v0.1.0-beta.4
      MD
      yield Elio::Changelog.new(dir), dir
    end
  end

  test "assembles the fragments by heading, Upgrading first and named after the previous version" do
    with_repo("b-firewall.md" => "### Added\n\n- **Firewall tab**.\n\n### Fixed\n\n- A bug.\n",
              "a-gandi.md" => "### Upgrading\n\n- Nothing to do.\n\n### Added\n\n- **Gandi**: long entry\n  on two lines.\n") do |changelog, _dir|
      assert_equal <<~MD, changelog.section
        ### Upgrading from 0.1.0-beta.4

        - Nothing to do.

        ### Added

        - **Gandi**: long entry
          on two lines.
        - **Firewall tab**.

        ### Fixed

        - A bug.
      MD
    end
  end

  test "release! writes the dated section, the links, and deletes the fragments but the README" do
    with_repo("x.md" => "### Changed\n\n- Something.\n") do |changelog, dir|
      changelog.release!("0.1.0-beta.5", date: Date.new(2026, 11, 20))
      text = File.read(File.join(dir, "CHANGELOG.md"))
      assert_includes text, "## [Unreleased]\n\n## [0.1.0-beta.5] — 2026-11-20\n\n### Changed\n\n- Something.\n\n## [0.1.0-beta.4]"
      assert_includes text, "[Unreleased]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.5...HEAD\n[0.1.0-beta.5]: https://github.com/elio-fleet/elio/compare/v0.1.0-beta.4...v0.1.0-beta.5\n[0.1.0-beta.4]:"
      assert_equal [ "README.md" ], Dir.children(File.join(dir, "changelog.d"))
      assert_raises(Elio::Changelog::Error) { changelog.release!("0.1.0-beta.6") }
    end
  end

  test "a malformed fragment is refused with its file and line" do
    { "### Notes\n- x\n" => /bad.md:1: unknown heading/, "- x\n" => /bad.md:1: an entry before any heading/,
      "### Added\nplain text\n" => /bad.md:2: expected/, "\n" => /bad.md: empty fragment/ }.each do |text, message|
      with_repo("bad.md" => text) { |changelog, _| assert_match message, assert_raises(Elio::Changelog::Error) { changelog.entries }.message }
    end
  end

  test "the fragments of the repository are well formed" do
    Elio::Changelog.new(Rails.root.to_s).entries
  end
end
