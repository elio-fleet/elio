# Reads the authorized keys of a server (every account Elio can read: see
# Keys::AuthorizedKeysReader.call_all) and refreshes its AccountSnapshots and
# the server's SSH status. Never raises.
class Keys::ServerScan
  Result = Data.define(:error_title) do
    def success? = error_title.nil?
  end

  def self.call(server, **connection_options)
    read = Keys::AuthorizedKeysReader.call_all(server, **connection_options)

    if read.success?
      server.record_ssh_status!(true)
      AccountSnapshot.record_all!(server, read)
    elsif read.reason == :key_refused
      server.record_ssh_status!(false)
    end
    Result.new(error_title: read.error_title)
  end
end
