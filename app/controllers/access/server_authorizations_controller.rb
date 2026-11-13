# Adds a key on an account of a server: the login one by default, or another
# one (account, or account=other + other_account) through root. A key of the
# keyring (public_key_id), or a new key (source=new, public_key[…]) saved to
# the keyring first. Optional duration (temporary access).
class ServerAuthorizationsController < ApplicationController
  include AuthorizedKeysRefresh

  require_permission :operate

  def create
    server = Server.find(params[:server_id])
    duration = requested_duration
    account = requested_account(server) or return redirect_to(server_path(server, tab: "keys"), alert: t("server_authorizations_controller.invalid_account"), status: :see_other)
    public_key = params[:source] == "new" ? create_public_key(server) : PublicKey.find(params.expect(:public_key_id))
    return unless public_key

    result = Keys::AccessGrant.call(server, public_key, account: account, duration: duration)
    respond_with_authorized_keys_refresh(account, *grant_message(server, account, public_key, result, duration),
                                         streams: [ turbo_stream.replace(helpers.dom_id(server, :add_key), partial: "servers/add_key_dialog", locals: { server: server }) ])
  end

  private

  # nil (permanent) or one of TemporaryAccess::DURATIONS.
  def requested_duration
    TemporaryAccess.duration_for(params[:duration]) if params[:duration].present?
  rescue ArgumentError
    raise ActionController::BadRequest, "Invalid duration"
  end

  # The login account (default), or the account named, checked like useradd
  # does; nil when the name is invalid.
  def requested_account(server)
    name = params[:account] == "other" ? params[:other_account].to_s.strip : params[:account]
    AuthorizedKeysAccount.for(server, name)
  end

  # Saves the new key to the keyring, or shows the dialog again with the errors.
  def create_public_key(server)
    public_key = PublicKey.new(params.expect(public_key: [ :name, :kind, :content, :description ]))
    if public_key.save
      Activity.record!(:public_key_created, public_key: public_key, fingerprint: public_key.fingerprint)
      @created = true
      return public_key
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(server, :add_key), partial: "servers/add_key_dialog",
                                                  locals: { server: server, public_key: public_key, source: "new", open: true }),
               status: :unprocessable_entity
      end
      format.html do
        redirect_to server_path(server, tab: "keys"), alert: t("server_authorizations_controller.not_saved", full_messages_to_sentence: public_key.errors.full_messages.to_sentence), status: :see_other
      end
    end
    nil
  end

  def grant_message(server, account, public_key, result, duration)
    target = t("server_authorizations_controller.target", server_name: account.login? ? server.name : "#{server.name} (#{account.unix_user})")
    name = (@created ? t("server_authorizations_controller.name_created", public_key_name: public_key.name) : t("server_authorizations_controller.name", public_key_name: public_key.name))

    if result.added? && duration
      [ :notice, t("server_authorizations_controller.added_for", name: name, target: target, label_for: (TemporaryAccess.label_for(duration)), date: (l(duration.from_now, format: :short))) ]
    elsif result.added?
      [ :notice, t("server_authorizations_controller.added", name: name, target: target) ]
    elsif result.already_present?
      [ :notice, t("server_authorizations_controller.present", name: name, target: target) ]
    else
      [ :alert, t(@created ? "server_authorizations_controller.failed_kept" : "server_authorizations_controller.failed", public_key_name: public_key.name, target: target, error_title: result.error_title, error_details: result.error_details) ]
    end
  end
end
