# A Unix account of a server whose authorized_keys Elio reads: the SSH user
# Elio logs in as (`server.username`), where keys are added, or another
# account read through root (listed and removed only).
class AuthorizedKeysAccount
  # Unix user names Elio accepts from a request (as useradd does).
  NAME_FORMAT = /\A[a-z_][a-z0-9_.-]{0,31}\$?\z/i
  # The same rule for an <input pattern> (checked again on the server).
  NAME_PATTERN = "[A-Za-z_][A-Za-z0-9_.\-]{0,31}\$?"

  attr_reader :server, :unix_user

  def self.login(server) = new(server)

  def self.for(server, unix_user)
    unix_user = unix_user.to_s
    return login(server) if unix_user.blank? || unix_user == server.username

    new(server, unix_user) if unix_user.match?(NAME_FORMAT)
  end

  # The other accounts Elio read on the server (root first), offered when adding a key.
  def self.others(server)
    AccountSnapshot.where(server: server).where.not(unix_user: server.username).pluck(:unix_user).sort_by { |user| [ user == "root" ? 0 : 1, user ] }
  end

  def initialize(server, unix_user = server.username)
    @server = server
    @unix_user = unix_user
  end

  def name = unix_user

  def login? = unix_user == server.username

  def path = "~#{unix_user}/.ssh/authorized_keys"

  # [title, details] to display for an Ssh::Connection error.
  def error_for(error) = [ error.title, error.message ]

  def ==(other) = other.is_a?(self.class) && other.server == server && other.unix_user == unix_user
  alias eql? ==

  def hash = [ self.class, server, unix_user ].hash
end
