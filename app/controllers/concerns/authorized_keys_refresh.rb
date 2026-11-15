# Shared by actions working on a server's authorized_keys (see
# AuthorizedKeysAccount): shows a read of every account (the key list frame),
# and after a change (Keys::ServerKeysChange) replaces that list with the read
# made on the change's own connection and shows the flash over Turbo Stream,
# or redirects to the server page without JavaScript.
module AuthorizedKeysRefresh
  extend ActiveSupport::Concern

  private

  # What server_authorized_keys/list needs for `read` (Keys::AuthorizedKeysReader.call_all).
  # A successful read proves the app can log in (and refreshes the account
  # snapshots); a refused key proves it cannot.
  def assign_authorized_keys(server, read)
    @server = server
    @result = read
    if read.success?
      server.record_ssh_status!(true)
      AccountSnapshot.record_all!(server, read)
    elsif read.reason == :key_refused
      server.record_ssh_status!(false)
    end
    @app_key = SshKey.app_keys
    @public_keys_by_fingerprint = PublicKey.where(fingerprint: read.keys.map(&:fingerprint)).index_by(&:fingerprint)
    @integration_keys = Integration.known_keys
    @temporary_accesses = TemporaryAccess.active.where(server: server).index_by { |access| [ access.unix_user, access.fingerprint ] }
  end

  # `read`: the list to show, or nil to reload it (nothing was sent to the
  # server). `streams`: extra Turbo Stream actions (e.g. closing a dialog).
  def respond_with_authorized_keys_refresh(server, read, flash_type, message, streams: [])
    assign_authorized_keys(server, read) if read
    respond_to do |format|
      format.turbo_stream do
        flash.now[flash_type] = message
        list = read ? { partial: "server_authorized_keys/list" } : { partial: "server_authorized_keys/frame", locals: { server: server, loading: :eager } }
        render turbo_stream: [
          turbo_stream.replace(helpers.dom_id(server, :authorized_keys), **list),
          turbo_stream.update("flash", partial: "shared/flash"),
          *streams
        ]
      end
      format.html { redirect_to server_path(server, tab: "keys"), flash: { flash_type => message }, status: :see_other }
    end
  end
end
