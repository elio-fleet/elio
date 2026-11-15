require "test_helper"

class Keys::AccessExtensionTest < ActiveSupport::TestCase
  include LocalShellHelpers
  include TemporaryAccessHelpers

  setup do
    @known_hosts = Rails.root.join("tmp", "test", "ssh-#{SecureRandom.hex(4)}", "known_hosts")
    setup_temp_home
    @public_key = public_keys(:ci)
    @type, @blob = @public_key.content.split(" ")
    @other = Ssh::KeyGenerator.generate(comment: "bob").public_key.strip
  end

  teardown do
    FileUtils.rm_rf(@known_hosts.dirname)
    teardown_temp_home
  end

  def write_keys(content)
    authorized_keys_file.dirname.mkpath
    authorized_keys_file.write(content)
  end

  def extend_access(access, duration = 1.hour, fake: FakeSsh.new(handler: local_shell))
    Keys::AccessExtension.call(access, duration, transport: fake, known_hosts_file: @known_hosts)
  end

  test "the script changes only the expiry of the key's lines, keeping its other options, its comment and the other lines" do
    write_keys(%(# team\nfrom="10.0.0.0/8",expiry-time="20261003144218Z" #{@type} #{@blob} CI deploy\n#{@other}\n))

    assert_equal "extended", run_local_script(Keys::AccessExtension.command(@blob, "20300101000000Z"))
    assert_equal %(# team\nfrom="10.0.0.0/8",expiry-time="20300101000000Z" #{@type} #{@blob} CI deploy\n#{@other}\n), authorized_keys_file.read
    assert_equal [ "authorized_keys" ], authorized_keys_file.dirname.children.map { |path| path.basename.to_s }
  end

  test "the script leaves a permanent line, another key's expiry and a missing file alone" do
    assert_equal "absent", run_local_script(Keys::AccessExtension.command(@blob, "20300101000000Z"))

    content = %(#{@type} #{@blob} CI\nexpiry-time="20261003144218Z" #{@other}\n)
    write_keys(content)
    assert_equal "absent", run_local_script(Keys::AccessExtension.command(@blob, "20300101000000Z"))
    assert_equal content, authorized_keys_file.read
  end

  test "extends the access from its current end, on the server and in Elio, and logs it" do
    access = create_temporary_access(expires_at: 20.minutes.from_now.change(usec: 0))
    access.update!(expiry_reminded_at: Time.current)
    previous_end = access.expires_at
    write_keys(%(expiry-time="#{previous_end.utc.strftime("%Y%m%d%H%M%S")}Z" #{@type} #{@blob} CI\n))

    result = extend_access(access, 4.hours)

    assert result.success?
    access.reload
    assert_equal previous_end + 4.hours, access.expires_at
    assert_equal 1, access.extensions_count
    assert_nil access.expiry_reminded_at, "a new reminder before the new end"
    assert_equal %(expiry-time="#{access.expires_at.utc.strftime("%Y%m%d%H%M%S")}Z" #{@type} #{@blob} CI\n), authorized_keys_file.read
    activity = Activity.of_kind(:key_access_extended).sole
    assert_equal [ servers(:web), "deploy", 4.hours.to_i ], [ activity.server, activity.unix_user, activity.data["duration_seconds"] ]
    assert_match "prolongé de 4 heures", activity.summary
  end

  test "an access past its end or already ended is not extended, without connecting" do
    never = FakeSsh.new(handler: ->(_command) { flunk "no connection" })
    [ create_temporary_access(expires_at: 1.minute.ago), create_temporary_access(public_key: public_keys(:alice)).tap(&:end!) ].each do |access|
      result = extend_access(access, fake: never)

      assert_equal [ :error, "Accès déjà terminé" ], [ result.status, result.error_title ]
    end
    assert_not Activity.of_kind(:key_access_extended).exists?
  end

  test "a key no longer on the server with an expiry is reported, the access left as it was" do
    access = create_temporary_access
    write_keys("#{@type} #{@blob} CI\n")

    result = extend_access(access)

    assert_equal [ :error, "Clé introuvable" ], [ result.status, result.error_title ]
    assert_equal 0, access.reload.extensions_count
  end

  test "returns the SSH error when the connection fails" do
    result = extend_access(create_temporary_access, fake: FakeSsh.new(error: Errno::ECONNREFUSED.new))

    assert_equal [ :error, "Connexion impossible" ], [ result.status, result.error_title ]
  end
end
