require "test_helper"

class Inventory::UnitJournalTest < ActiveSupport::TestCase
  setup do
    @known_hosts = Pathname(Dir.mktmpdir).join("known_hosts")
  end

  teardown do
    FileUtils.rm_rf(@known_hosts.dirname)
  end

  def read(fake, unit = "nginx.service")
    Inventory::UnitJournal.call(servers(:web), unit, transport: fake, known_hosts_file: @known_hosts)
  end

  test "reads the last lines of the unit's journal, through sudo when it has it" do
    journal = "2026-11-15T10:00:01+0000 web nginx[812]: bind() to 0.0.0.0:80 failed (98: Address already in use)\n" \
              "2026-11-15T10:00:01+0000 web systemd[1]: nginx.service: Failed with result 'exit-code'.\n"
    fake = FakeSsh.new(responses: { "sudo -n true" => FakeSsh::Response.new("", "", 0),
                                    "sudo -n journalctl --unit=nginx.service --lines=50 --no-pager --quiet --output=short-iso" => FakeSsh::Response.new(journal, "", 0) })

    result = read(fake)

    assert result.success?
    assert_equal 2, result.lines.size
    assert_match "Address already in use", result.lines.first
  end

  test "a long line is cut, and the error of the command is kept" do
    fake = FakeSsh.new(handler: ->(command) { command.start_with?("journalctl") ? FakeSsh::Response.new("#{"x" * 5000}\n", "", 0) : nil })
    assert_equal Inventory::UnitJournal::LINE_LENGTH, read(fake).lines.first.size

    refused = FakeSsh.new(handler: ->(command) { FakeSsh::Response.new("", "Failed to get journal access: Permission denied\n", 1) if command.start_with?("journalctl") })
    result = read(refused)
    assert_not result.success?
    assert_equal "Failed to get journal access: Permission denied", result.error
  end

  test "an SSH failure is an error, not an exception" do
    result = read(FakeSsh.new(error: Net::SSH::AuthenticationFailed.new("deploy")))
    assert_not result.success?
    assert_match "deploy", result.error
  end

  test "only systemd unit names are accepted" do
    %w[nginx.service mnt-backup.mount getty@tty1.service mnt-my\x2dshare.mount systemd-fsck@dev-disk-by\x2duuid-1234.service docker.socket].each do |name|
      assert Inventory::UnitJournal.valid_name?(name), name
    end
    [ "nginx", "-x.service", "a b.service", "a;reboot.service", "$(id).service", "a'.service", "a\n.service", "../x.service", "", nil, "#{"a" * 300}.service" ].each do |name|
      assert_not Inventory::UnitJournal.valid_name?(name), name.inspect
    end
    assert_raises(ArgumentError) { read(FakeSsh.new, "nginx; reboot") }
  end

  test "the unit name stays one word in the command sent" do
    command = Ssh::Commands.render("inventory.unit_journal", unit: 'mnt-my\x2dshare.mount', lines: 50)
    words = Shellwords.split(command)
    assert_includes words, '--unit=mnt-my\x2dshare.mount'
  end

  test "the restart command to copy, with sudo unless logged in as root" do
    assert_equal "sudo systemctl restart nginx.service", Inventory::UnitJournal.restart_command(servers(:web), "nginx.service")
    servers(:web).username = "root"
    assert_equal 'systemctl restart mnt-my\\\\x2dshare.mount', Inventory::UnitJournal.restart_command(servers(:web), 'mnt-my\x2dshare.mount')
  end
end
