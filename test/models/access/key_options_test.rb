require "test_helper"

class KeyOptionsTest < ActiveSupport::TestCase
  test "nothing given: no options, valid" do
    options = KeyOptions.from_params({})

    assert options.valid?
    assert options.empty?
    assert_equal "", options.to_s
  end

  test "the three options, in OpenSSH syntax, spaces of from= removed" do
    options = KeyOptions.from_params("from" => " 10.0.0.0/8, !10.0.0.5,*.example.com ", "command" => " /usr/bin/rrsync -ro /srv/backup ", "no_port_forwarding" => "1")

    assert options.valid?
    assert_equal [ 'from="10.0.0.0/8,!10.0.0.5,*.example.com"', 'command="/usr/bin/rrsync -ro /srv/backup"', "no-port-forwarding" ], options.to_a
  end

  test "a double quote of the command is escaped, so it cannot end the option" do
    options = KeyOptions.new(command: %(echo "hi",no-pty \\"x))

    assert options.valid?
    assert_equal %(command="echo \\"hi\\",no-pty \\\\"x"), options.to_s
  end

  test "refuses a from= that is not a list of addresses or names" do
    [ %(10.0.0.1",command="sh), "10.0.0.1 ;id", "a,,b", "10.0.0.1=", "x" * 201 ].each do |value|
      options = KeyOptions.new(from: value)

      assert_not options.valid?, value
      assert_equal [ :from ], options.errors
      assert options.empty?, "an invalid value is never written"
    end
  end

  test "refuses a command with a control character, a trailing backslash or too long" do
    [ "ls\nid", "ls\tid", "l\u0000s", "ls \\", "é", "x" * 301 ].each do |value|
      options = KeyOptions.new(command: value)

      assert_not options.valid?, value.inspect
      assert_equal [ :command ], options.errors
    end
  end

  test "error messages are translated" do
    options = KeyOptions.new(from: "a b;c", command: "a\nb")

    assert_equal 2, options.error_messages.size
    assert_match "adresses d'origine", options.error_messages.first
  end

  test "no-port-forwarding only when ticked" do
    assert_equal [], KeyOptions.from_params("no_port_forwarding" => "0").to_a
    assert_equal [ "no-port-forwarding" ], KeyOptions.from_params("no_port_forwarding" => "1").to_a
  end
end
