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

  # The keys of an account (`unreadable`: a file root could not read).
  AccountKeys = Data.define(:account, :keys, :unreadable) do
    def initialize(account:, keys:, unreadable: false) = super
  end

  # Every account of the server: `accounts` = the login one (always first),
  # then, when Elio has root, the other accounts with a login shell and an
  # authorized_keys file (root first). `privileged` false: only the login one.
  All = Data.define(:accounts, :privileged, :error_title, :error_details, :reason) do
    def initialize(accounts:, privileged:, error_title: nil, error_details: nil, reason: nil) = super
    def success? = error_title.nil?
    def keys = accounts.flat_map(&:keys)
    def login = accounts.first
  end

  def self.call_all(server, **connection_options)
    login = AuthorizedKeysAccount.login(server)
    accounts, privileged = Ssh::Connection.open(server, **connection_options) do |ssh|
      own = AccountKeys.new(account: login, keys: AuthorizedKey.parse(ssh.run_command!("keys.read").stdout))
      next [ [ own ], false ] unless ssh.privileged?

      others = parse_accounts(ssh.run_command("keys.read_accounts").stdout).except(server.username).map do |user, (content, unreadable)|
        AccountKeys.new(account: AuthorizedKeysAccount.new(server, user), keys: AuthorizedKey.parse(content), unreadable: unreadable)
      end
      [ [ own, *others.sort_by { |entry| [ entry.account.unix_user == "root" ? 0 : 1, entry.account.unix_user ] } ], true ]
    end

    All.new(accounts: accounts, privileged: privileged)
  rescue Ssh::Connection::Error => e
    title, details = login.error_for(e)
    All.new(accounts: [], privileged: false, error_title: title, error_details: details, reason: e.reason)
  end

  # "@@elio account root\n<lines>\n@@elio account bob\n@@elio unreadable\n" →
  # { "root" => ["<lines>", false], "bob" => ["", true] }
  def self.parse_accounts(text)
    current = nil
    text.to_s.lines.each_with_object({}) do |line, accounts|
      if (user = line[/\A@@elio account (\S+)\s*\z/, 1])
        current = accounts[user] = [ +"", false ]
      elsif current && line.start_with?("@@elio unreadable")
        current[1] = true
      elsif current
        current[0] << line
      end
    end
  end

  # The commands sent (config/ssh_commands.yml: keys.read, keys.read_accounts), also run locally by the tests.
  def self.command = Ssh::Commands.render("keys.read")
  def self.accounts_command = Ssh::Commands.render("keys.read_accounts")
end
