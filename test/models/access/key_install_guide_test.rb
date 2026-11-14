require "test_helper"

class KeyInstallGuideTest < ActiveSupport::TestCase
  def key = ssh_keys(:main)

  test "root by default: appends the key to the account running it" do
    guide = KeyInstallGuide.new(key)

    assert_equal "root", guide.account
    assert_equal "mkdir -p ~/.ssh && chmod 700 ~/.ssh && " \
                 "{ grep -qxF '#{key.public_key}' ~/.ssh/authorized_keys 2>/dev/null || echo '#{key.public_key}' >> ~/.ssh/authorized_keys; } && " \
                 "chmod 600 ~/.ssh/authorized_keys", guide.command
    assert_nil guide.sudoers_command
    assert_nil guide.username
    assert_empty guide.errors
  end

  test "an unknown account falls back to root" do
    assert_equal "root", KeyInstallGuide.new(key, account: "admin").account
  end

  test "a sudo account runs the same command and gets a password-less sudo line" do
    guide = KeyInstallGuide.new(key, account: "sudo", username: "ignored")

    assert_equal KeyInstallGuide.new(key).command, guide.command
    assert_nil guide.username
    assert_equal %(echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/elio >/dev/null && sudo chmod 440 /etc/sudoers.d/elio), guide.sudoers_command
  end

  test "a dedicated account is created when missing, then gets the key in its own home" do
    guide = KeyInstallGuide.new(key, account: "dedicated", username: " monitor ")

    assert_equal "monitor", guide.username
    assert_equal "id -u monitor >/dev/null 2>&1 || useradd -m -s /bin/bash monitor && " \
                 "install -d -m 700 -o monitor -g \"$(id -gn monitor)\" ~monitor/.ssh && " \
                 "{ grep -qxF '#{key.public_key}' ~monitor/.ssh/authorized_keys 2>/dev/null || echo '#{key.public_key}' >> ~monitor/.ssh/authorized_keys; } && " \
                 "chown monitor: ~monitor/.ssh/authorized_keys && chmod 600 ~monitor/.ssh/authorized_keys", guide.command
    assert_nil guide.sudoers_command
  end

  test "the dedicated account is called elio unless named, and never takes a name that could break the command" do
    assert_equal "elio", KeyInstallGuide.new(key, account: "dedicated").username

    [ "x; rm -rf /", "root", "Ünicode", "a" * 40 ].each do |name|
      guide = KeyInstallGuide.new(key, account: "dedicated", username: name)
      assert_equal "elio", guide.username, name
      assert_equal [ :username ], guide.errors, name
    end
  end

  test "restricts the key to Elio's address with from=" do
    guide = KeyInstallGuide.new(key, from: " 203.0.113.10, 10.0.0.0/8 ")

    assert_equal "203.0.113.10,10.0.0.0/8", guide.from
    assert_equal %(from="203.0.113.10,10.0.0.0/8" #{key.public_key}), guide.authorized_keys_line
    assert_includes guide.command, %(echo 'from="203.0.113.10,10.0.0.0/8" #{key.public_key}' >> ~/.ssh/authorized_keys)
    assert_includes KeyInstallGuide.new(key, account: "dedicated", from: "2001:db8::/32").command, %(echo 'from="2001:db8::/32" #{key.public_key}')
  end

  test "an address that could break the line is refused and the key stays unrestricted" do
    [ %(1.2.3.4" command="sh), "1.2.3.4'", "a" * 201, "1.2.3.4,,5.6.7.8" ].each do |from|
      guide = KeyInstallGuide.new(key, from: from)
      assert_nil guide.from, from
      assert_equal [ :from ], guide.errors, from
      assert_equal key.public_key, guide.authorized_keys_line
    end
  end

  test "running the command twice installs the key once, other keys kept" do
    Dir.mktmpdir do |home|
      other = public_keys(:alice).content
      FileUtils.mkdir_p("#{home}/.ssh")
      File.write("#{home}/.ssh/authorized_keys", "#{other}\n")
      command = KeyInstallGuide.new(key, from: "203.0.113.10").command

      2.times { assert system({ "HOME" => home }, "sh", "-c", command), command }

      assert_equal [ other, %(from="203.0.113.10" #{key.public_key}) ], File.read("#{home}/.ssh/authorized_keys").lines(chomp: true)
      assert_equal "600", format("%o", File.stat("#{home}/.ssh/authorized_keys").mode & 0o777)
    end
  end

  test "the line Elio's own parser reads back still matches the key" do
    line = KeyInstallGuide.new(key, from: "203.0.113.10").authorized_keys_line
    parsed = AuthorizedKey.parse(line).first

    assert_equal %(from="203.0.113.10"), parsed.options
    assert parsed.matches?(key)
  end
end
