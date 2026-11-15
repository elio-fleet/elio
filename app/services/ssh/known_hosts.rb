# The host keys pinned by Ssh::Connection (trust on first use), in `file`
# (Ssh::Connection::KNOWN_HOSTS_FILE by default, replaced in tests).
module Ssh::KnownHosts
  # One pinned key: its type ("ssh-ed25519") and SHA256 fingerprint.
  Entry = Data.define(:type, :fingerprint)

  class << self
    attr_writer :file

    def file = Pathname(@file || Ssh::Connection::KNOWN_HOSTS_FILE)

    # Removes the entries of host:port. Returns the number of removed lines.
    def forget(host, port, file: self.file)
      file = Pathname(file)
      return 0 unless file.exist?

      lines = file.readlines
      kept = lines.reject { |line| entry_for?(line, host, port) }
      file.write(kept.join) if kept.size != lines.size
      lines.size - kept.size
    end

    # SHA256 fingerprints ("SHA256:…", like `ssh-keygen -l`) pinned for host:port.
    def fingerprints(host, port, file: self.file) = entries(host, port, file: file).map(&:fingerprint)

    # The keys pinned for host:port, as Entry (unreadable lines are skipped).
    def entries(host, port, file: self.file)
      lines_for(host, port, file).filter_map do |line|
        _, type, blob = line.split
        Entry.new(type: type, fingerprint: Ssh::KeyGenerator.fingerprint(Base64.strict_decode64(blob))) if blob
      rescue ArgumentError
        nil
      end
    end

    # Replaces the pins of host:port by the known_hosts lines of `source`
    # (a file net-ssh pinned them in) for that host. Returns the new entries.
    def replace(host, port, source:, file: self.file)
      file = Pathname(file)
      lines = lines_for(host, port, source)
      forget(host, port, file: file)
      file.dirname.mkpath
      File.open(file, "a") { |out| lines.each { |line| out.write(line.end_with?("\n") ? line : "#{line}\n") } }
      entries(host, port, file: file)
    end

    private

    def lines_for(host, port, file)
      file = Pathname(file)
      file.exist? ? file.readlines.select { |line| entry_for?(line, host, port) } : []
    end

    # net-ssh writes "host" for port 22 and "[host]:port" otherwise.
    def entry_for?(line, host, port)
      names = port.to_i == 22 ? [ host, "[#{host}]:22" ] : [ "[#{host}]:#{port}" ]
      (line.split.first.to_s.split(",") & names).any?
    end
  end
end
