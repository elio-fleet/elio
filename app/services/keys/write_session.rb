# The SSH connection a change to a server's authorized_keys runs on. It holds
# the server's key lock for as long as the connection is open, so two changes
# on one server (two operators, a request and the expiry job) wait for each
# other instead of rewriting the same file at the same time.
#
# `ssh`: a connection already opened by Keys::WriteSession.open (the lock is
# then already held), to run several changes and a read on one connection.
module Keys::WriteSession
  def self.open(server, ssh: nil, **connection_options, &block)
    return yield(ssh) if ssh

    AdvisoryLock.hold(lock_name(server)) { Ssh::Connection.open(server, **connection_options, &block) }
  end

  def self.lock_name(server) = "authorized_keys:server:#{server.id}"
end
