# Trusts the new host key of servers (reinstalled…), on an administrator's
# explicit request. Only the fingerprint the admin was shown is accepted: the
# server is contacted with an empty, temporary known_hosts file, and the pins
# of the real one are replaced only if the key it presents now matches. The
# old pins stay otherwise, so the server stays blocked.
#
#   Ssh::HostKeyTrust.call(server, "SHA256:…", user: admin)              # => Result
#   Ssh::HostKeyTrust.call_many([ [ server, "SHA256:…" ], … ], user: admin) # => [Result]
module Ssh::HostKeyTrust
  # status: :accepted, :changed_again (the server presents yet another key)
  # or :unreachable (no key could be read).
  Result = Data.define(:server, :status, :fingerprint) do
    def accepted? = status == :accepted
  end

  # Where each key type lives on a Debian / Ubuntu server, for `ssh-keygen -lf`.
  KEY_FILES = { "ssh-ed25519" => "ed25519", "ssh-rsa" => "rsa", "ssh-dss" => "dsa" }.freeze

  class << self
    def call(server, fingerprint, user:) = call_many([ [ server, fingerprint ] ], user: user).first

    # Contacts the servers in parallel, then pins and logs on this thread.
    def call_many(pairs, user:)
      Dir.mktmpdir("elio-host-keys") do |dir|
        files = BoundedParallel.map(pairs) { |server, _| present(server, Pathname(dir).join("known_hosts-#{server.id}")) }
        pairs.zip(files).map { |(server, fingerprint), file| trust(server, fingerprint, file, user) }
      end
    end

    # The command an admin runs on the server's console to read the
    # fingerprint of its key of this type.
    def verify_command(type)
      name = KEY_FILES[type] || (type.to_s.start_with?("ecdsa-") ? "ecdsa" : "ed25519")
      "ssh-keygen -lf /etc/ssh/ssh_host_#{name}_key.pub"
    end

    # A key of a type none of the pinned keys has (a new algorithm), rather
    # than the same type of key replaced.
    def new_algorithm?(type, known_types)
      type.present? && known_types.any? && known_types.exclude?(type)
    end

    private

    # Pins whatever the server presents (accept_new) in `file`.
    def present(server, file)
      Ssh::Check.call(server, known_hosts_file: file)
      file
    end

    def trust(server, fingerprint, file, user)
      presented = Ssh::KnownHosts.entries(server.host, server.port, file: file)
      return Result.new(server: server, status: :unreachable, fingerprint: fingerprint) if presented.empty?

      entry = presented.find { |candidate| candidate.fingerprint == fingerprint }
      return Result.new(server: server, status: :changed_again, fingerprint: fingerprint) unless entry

      previous = Ssh::KnownHosts.entries(server.host, server.port)
      Ssh::KnownHosts.replace(server.host, server.port, source: file)
      Activity.record!(:host_key_changed, server: server, user: user, new_fingerprint: fingerprint, key_type: entry.type,
                                          previous_fingerprints: previous.map(&:fingerprint),
                                          new_algorithm: new_algorithm?(entry.type, previous.map(&:type)))
      Result.new(server: server, status: :accepted, fingerprint: fingerprint)
    end
  end
end
