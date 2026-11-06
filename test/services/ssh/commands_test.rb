require "test_helper"
require "open3"

class Ssh::CommandsTest < ActiveSupport::TestCase
  include LocalShellHelpers

  test "every command is described, has a default variant, and only keys.* write" do
    commands = Ssh::Commands.all
    assert_operator commands.size, :>=, 15
    commands.each_value do |command|
      assert command.description.present?, "#{command.key}: description"
      assert command.variants.key?("default"), "#{command.key}: default variant"
      assert_includes %w[user root], command.run_as, command.key
      assert_operator command.timeout, :<=, (command.key.end_with?("_scan") ? 300 : 120), command.key
      assert_equal command.key.start_with?("keys.") && !command.key.start_with?("keys.read"), command.writes?, "#{command.key}: writes"
    end
  end

  test "the variants of a command take the same values" do
    Ssh::Commands.all.each_value do |command|
      placeholders = command.variants.values.map { |template| template.scan(Ssh::Commands::PLACEHOLDER).flatten.sort.uniq }
      assert_equal 1, placeholders.uniq.size, "#{command.key}: #{placeholders.inspect}"
    end
  end

  test "every command of the file is used by the application, and nothing is sent outside of it" do
    code = Dir[Rails.root.join("app/**/*.rb")].to_h { |path| [ path, File.read(path) ] }
    Ssh::Commands.all.each_key do |key|
      assert code.values.any? { |source| source.include?(%("#{key}")) }, "#{key} is not used"
    end
    code.each do |path, source|
      next if path.end_with?("app/services/ssh/connection.rb")

      assert_no_match(/\.exec!?\(/, source, "#{path} sends a command outside config/ssh_commands.yml")
    end
  end

  test "the variant of the distribution family, else the default one" do
    health = Ssh::Commands.fetch("inventory.health")
    assert_match "apt-get -s", health.template(%w[ubuntu debian])
    assert_match "apt-get -s", health.template(%w[debian])
    default = health.template(%w[rocky rhel centos fedora])
    assert_no_match "apt-get", default
    assert_equal default, health.template
    assert Ssh::Commands.fetch("inventory.health").distro_specific?
    assert_not Ssh::Commands.fetch("inventory.os").distro_specific?
  end

  test "scripts are sent with sh -c, single commands as they are" do
    assert Ssh::Commands.render("inventory.os").start_with?("sh -c ")
    assert_equal "sudo -n true", Ssh::Commands.render("connection.sudo_probe")
    assert_equal "echo abc-123", Ssh::Commands.render("connection.check", token: "abc-123")
  end

  test "values are shell-escaped: they can never break out of their word" do
    setup_temp_home
    hostile = "AAAA'; touch #{@home}/pwned; echo '"
    command = Ssh::Commands.render("keys.append", line: "ssh-ed25519 #{hostile} $(touch #{@home}/pwned2)", blob: hostile)

    stdout, status = Open3.capture2({ "HOME" => @home.to_s }, "sh", "-c", command)
    assert status.success?
    assert_equal "added", stdout.strip
    assert_not @home.join("pwned").exist?
    assert_not @home.join("pwned2").exist?
    assert_includes @home.join(".ssh/authorized_keys").read, "$(touch"
  ensure
    teardown_temp_home
  end

  test "a missing value or an unknown command is an error" do
    assert_raises(Ssh::Commands::MissingValue) { Ssh::Commands.render("keys.remove") }
    assert_raises(Ssh::Commands::UnknownCommand) { Ssh::Commands.fetch("inventory.nope") }
  end

  test "parses the distribution family" do
    assert_equal %w[ubuntu debian], Ssh::Commands.parse_distros("ubuntu debian\n")
    assert_equal %w[rocky rhel centos fedora], Ssh::Commands.parse_distros("rocky rhel centos fedora")
    assert_empty Ssh::Commands.parse_distros("")
  end

  test "the parsers agree with the commands" do
    containers = Ssh::Commands.render("inventory.docker_containers")
    Inventory::Collectors::Services::LABELS.each { |label| assert_includes containers, %(.Label "#{label}") }
    Ssh::Commands.fetch("inventory.health").variants.each_value do |template|
      assert_includes template, Inventory::Collectors::Health::EXCLUDED_FILESYSTEMS.map { |type| "-x #{type}" }.join(" ")
    end
  end
end
