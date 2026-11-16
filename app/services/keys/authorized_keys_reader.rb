# Reads the authorized_keys file of an account (see AuthorizedKeysAccount) and
# parses it into AuthorizedKey objects. A missing file means no keys. Never
# raises: failures are returned in the Result.
class Keys::AuthorizedKeysReader
  Result = Data.define(:keys, :error_title, :error_details, :reason) do
    def initialize(keys:, error_title:, error_details:, reason: nil) = super
    def success? = error_title.nil?
  end

  def self.call(server, account: nil, **connection_options)
    account ||= AuthorizedKeysAccount.login(server)
    output = Ssh::Connection.open(server, **connection_options) do |ssh|
      ssh.run_command!("keys.read").stdout
    end

    Result.new(keys: AuthorizedKey.parse(output), error_title: nil, error_details: nil)
  rescue Ssh::Connection::Error => e
    title, details = account.error_for(e)
    Result.new(keys: [], error_title: title, error_details: details, reason: e.reason)
  end

  # The keys of an account (`unreadable`: a file root could not read;
  # `missing_file`: no ~/.ssh/authorized_keys). `extra_files`: the other files
  # sshd reads keys from (AuthorizedKeysFile, e.g. ~/.ssh/authorized_keys2),
  # shown but never changed by Elio.
  AccountKeys = Data.define(:account, :keys, :unreadable, :missing_file, :extra_files) do
    def initialize(account:, keys:, unreadable: false, missing_file: false, extra_files: []) = super
    def extra_keys = extra_files.flat_map(&:keys)
  end

  # A file named by sshd's AuthorizedKeysFile, other than ~/.ssh/authorized_keys.
  ExtraFile = Data.define(:path, :keys)

  # Every account of the server: `accounts` = the login one (always first),
  # then, when Elio has root, the other accounts with a login shell and an
  # authorized_keys file (root first). `privileged` false: only the login one.
  # `dormant`: the accounts with a login shell but no key file at all (root only).
  All = Data.define(:accounts, :privileged, :dormant, :error_title, :error_details, :reason) do
    def initialize(accounts:, privileged:, dormant: [], error_title: nil, error_details: nil, reason: nil) = super
    def success? = error_title.nil?
    def keys = accounts.flat_map(&:keys)
    def login = accounts.first
    def for(account) = accounts.find { |entry| entry.account == account }
  end

  # `ssh`: an open connection to read on (after a change, see Keys::ServerKeysChange).
  def self.call_all(server, ssh: nil, **connection_options)
    login = AuthorizedKeysAccount.login(server)
    accounts, privileged, dormant = ssh ? read_all(ssh, login) : Ssh::Connection.open(server, **connection_options) { |connection| read_all(connection, login) }

    All.new(accounts: accounts, privileged: privileged, dormant: dormant)
  rescue Ssh::Connection::Error => e
    title, details = login.error_for(e)
    All.new(accounts: [], privileged: false, error_title: title, error_details: details, reason: e.reason)
  end

  # [accounts, privileged, dormant] read on the connection `ssh`.
  def self.read_all(ssh, login)
    server = login.server
    own_keys = AuthorizedKey.parse(ssh.run_command!("keys.read").stdout)
    return [ [ AccountKeys.new(account: login, keys: own_keys) ], false, [] ] unless ssh.privileged?

    sections = parse_accounts(ssh.run_command("keys.read_accounts").stdout)
    own = AccountKeys.new(account: login, keys: own_keys, extra_files: extra_files(sections[server.username]))
    others = sections.except(server.username).map do |user, section|
      AccountKeys.new(account: AuthorizedKeysAccount.new(server, user), keys: AuthorizedKey.parse(section.content), unreadable: section.unreadable,
                      missing_file: !section.file, extra_files: extra_files(section))
    end
    dormant, others = others.partition { |entry| entry.missing_file && entry.extra_keys.empty? }
    by_name = ->(entry) { [ entry.account.unix_user == "root" ? 0 : 1, entry.account.unix_user ] }
    [ [ own, *others.sort_by(&by_name) ], true, dormant.sort_by(&by_name).map { |entry| entry.account.unix_user } ]
  end
  private_class_method :read_all

  # The extra files of a section that hold at least one key.
  def self.extra_files(section)
    return [] unless section

    section.extra_files.map { |path, content| ExtraFile.new(path: path, keys: AuthorizedKey.parse(content)) }.select { |file| file.keys.any? }
  end
  private_class_method :extra_files

  # One account in the output of keys.read_accounts: its authorized_keys
  # (`file` false when it has none) and its other key files (path => content).
  Section = Struct.new(:content, :unreadable, :file, :extra_files)

  # "@@elio account root\n<lines>\n@@elio account bob\n@@elio unreadable\n@@elio no_file dave\n
  #  @@elio extra dave /home/dave/.ssh/authorized_keys2\n<lines>\n" →
  # { "root" => Section("<lines>", false, true, {}), "bob" => Section("", true, true, {}),
  #   "dave" => Section("", false, false, { "/home/dave/.ssh/authorized_keys2" => "<lines>" }) }
  def self.parse_accounts(text)
    accounts = {}
    section = ->(user) { accounts[user] ||= Section.new(+"", false, false, {}) }
    current = buffer = nil
    text.to_s.lines.each do |line|
      if (user = line[/\A@@elio account (\S+)\s*\z/, 1])
        current = section.call(user).tap { |entry| entry.file = true }
        buffer = current.content
      elsif (user = line[/\A@@elio no_file (\S+)\s*\z/, 1])
        section.call(user)
        current = buffer = nil
      elsif (match = line.match(/\A@@elio extra (\S+) (.+?)\s*\z/))
        current = nil
        buffer = section.call(match[1]).extra_files[match[2]] = +""
      elsif current && line.start_with?("@@elio unreadable")
        current.unreadable = true
      elsif buffer
        buffer << line
      end
    end
    accounts
  end

  # The commands sent (config/ssh_commands.yml: keys.read, keys.read_accounts), also run locally by the tests.
  def self.command = Ssh::Commands.render("keys.read")
  def self.accounts_command = Ssh::Commands.render("keys.read_accounts")
end
