# The commands an admin copies to install Elio's public key on a server, for
# the account Elio will log in with: root, an existing account with sudo, or a
# dedicated account without privileges. Optionally restricts the key to Elio's
# address (`from=`). Only shown on the settings page: Elio never runs them.
class KeyInstallGuide
  ACCOUNTS = %w[root sudo dedicated].freeze
  DEFAULT_DEDICATED_USER = "elio"
  # OpenSSH `from=` patterns: addresses, CIDR, host names, `*` / `?`, `!`, comma separated.
  FROM_FORMAT = %r{\A!?[0-9A-Za-z.:*?/-]+(,!?[0-9A-Za-z.:*?/-]+)*\z}
  SUDOERS_FILE = "/etc/sudoers.d/elio"

  attr_reader :ssh_key, :account, :username, :from, :errors

  def initialize(ssh_key, account: nil, username: nil, from: nil)
    @ssh_key = ssh_key
    @account = ACCOUNTS.include?(account) ? account : "root"
    @errors = []
    @username = account_username(username.to_s.strip)
    @from = restriction(from.to_s.gsub(/\s+/, ""))
  end

  def self.account_label(account) = I18n.t("key_install_guide.accounts.#{account}")

  def dedicated? = account == "dedicated"
  def sudo? = account == "sudo"

  # The authorized_keys line, with the `from=` option when one is given.
  def authorized_keys_line
    [ (%(from="#{from}") if from), ssh_key.public_key ].compact.join(" ")
  end

  # Run as root (root, dedicated) or as the account itself (sudo): appends the
  # line to the account's authorized_keys with the permissions sshd expects;
  # the dedicated account is created first when missing.
  def command
    return append_command("~") unless dedicated?

    home = "~#{username}"
    "id -u #{username} >/dev/null 2>&1 || useradd -m -s /bin/bash #{username} && " \
      "install -d -m 700 -o #{username} -g \"$(id -gn #{username})\" #{home}/.ssh && " \
      "echo '#{authorized_keys_line}' >> #{home}/.ssh/authorized_keys && " \
      "chown #{username}: #{home}/.ssh/authorized_keys && chmod 600 #{home}/.ssh/authorized_keys"
  end

  # Run as the sudo account: lets it become root without a password, as Elio
  # only uses `sudo -n` (README, "Preparing the servers"). Nil for the other accounts.
  def sudoers_command
    return unless sudo?

    "echo \"$(whoami) ALL=(ALL) NOPASSWD: ALL\" | sudo tee #{SUDOERS_FILE} >/dev/null && sudo chmod 440 #{SUDOERS_FILE}"
  end

  private

  def append_command(home)
    "mkdir -p #{home}/.ssh && chmod 700 #{home}/.ssh && echo '#{authorized_keys_line}' >> #{home}/.ssh/authorized_keys && chmod 600 #{home}/.ssh/authorized_keys"
  end

  # Only the dedicated account is named: root is root, and the sudo account
  # runs the command itself. An invalid name falls back to the default one.
  def account_username(value)
    return unless dedicated?
    return DEFAULT_DEDICATED_USER if value.empty?
    return value if value.match?(Server::USERNAME_FORMAT) && value != "root"

    @errors << :username
    DEFAULT_DEDICATED_USER
  end

  def restriction(value)
    return if value.empty?
    return value if value.length <= 200 && value.match?(FROM_FORMAT)

    @errors << :from
    nil
  end
end
