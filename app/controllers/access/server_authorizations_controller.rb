# Adds a key on accounts of a server: the login one by default, or the ones
# checked (accounts[], plus other_account typed in) through root, all on one
# connection (Keys::ServerKeysChange). A key of the keyring (public_key_id), or
# a new key (source=new, public_key[…]) saved to the keyring first. Optional
# duration (temporary access) and restrictions (key_options, see KeyOptions).
class ServerAuthorizationsController < ApplicationController
  include AuthorizedKeysRefresh

  require_permission :operate

  # Accounts written in one go, at most.
  MAX_ACCOUNTS = 20

  def create
    server = Server.find(params[:server_id])
    duration = requested_duration
    accounts = requested_accounts(server) or return back_to_keys(server, t("server_authorizations_controller.invalid_account"))
    return back_to_keys(server, t("server_authorizations_controller.no_account")) if accounts.empty?

    options = KeyOptions.from_params(params.permit(key_options: %i[from command no_port_forwarding])[:key_options]&.to_h || {})
    return back_to_keys(server, t("server_authorizations_controller.invalid_options", errors: options.error_messages.to_sentence)) unless options.valid?

    public_key = params[:source] == "new" ? create_public_key(server) : PublicKey.find(params.expect(:public_key_id))
    return unless public_key

    change = Keys::ServerKeysChange.grant(server, public_key, accounts: accounts, duration: duration, options: (options unless options.empty?))
    messages = change.outcomes.map { |account, result| grant_message(server, account, public_key, result, duration, options) }
    flash_type = messages.any? { |type, _| type == :alert } ? :alert : :notice
    respond_with_authorized_keys_refresh(server, change.read, flash_type, messages.map(&:last).join(" "),
                                         streams: [ turbo_stream.replace(helpers.dom_id(server, :add_key), partial: "servers/add_key_dialog", locals: { server: server }) ])
  end

  private

  # nil (permanent) or one of TemporaryAccess::DURATIONS.
  def requested_duration
    TemporaryAccess.duration_for(params[:duration]) if params[:duration].present?
  rescue ArgumentError
    raise ActionController::BadRequest, "Invalid duration"
  end

  # The accounts checked (accounts[], blanks ignored) or the one named
  # (account), "other" meaning other_account; the login account when none is
  # sent. Each name is checked like useradd does: nil when one is invalid.
  def requested_accounts(server)
    names = params.key?(:accounts) ? Array(params[:accounts]) : [ params[:account] ]
    names = names.map { |name| name == "other" ? "" : name.to_s }
    names << params[:other_account].to_s.strip if params[:account] == "other" || params[:other_account].present?
    names = names.reject(&:blank?).uniq
    names = [ server.username ] if names.empty? && !params.key?(:accounts)
    return if names.size > MAX_ACCOUNTS

    accounts = names.map { |name| AuthorizedKeysAccount.for(server, name) }
    accounts unless accounts.any?(&:nil?)
  end

  def back_to_keys(server, alert)
    redirect_to server_path(server, tab: "keys"), alert: alert, status: :see_other
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

  def grant_message(server, account, public_key, result, duration, options)
    target = t("server_authorizations_controller.target", server_name: account.login? ? server.name : "#{server.name} (#{account.unix_user})")
    name = (@created ? t("server_authorizations_controller.name_created", public_key_name: public_key.name) : t("server_authorizations_controller.name", public_key_name: public_key.name))

    if result.added? && duration
      [ :notice, t("server_authorizations_controller.added_for", name: name, target: target, label_for: (TemporaryAccess.label_for(duration)), date: (l(duration.from_now, format: :short))) ]
    elsif result.added?
      [ :notice, t("server_authorizations_controller.added", name: name, target: target) ]
    elsif result.already_present?
      [ :notice, t(options.empty? ? "server_authorizations_controller.present" : "server_authorizations_controller.present_options_kept", name: name, target: target) ]
    else
      [ :alert, t(@created ? "server_authorizations_controller.failed_kept" : "server_authorizations_controller.failed", public_key_name: public_key.name, target: target, error_title: result.error_title, error_details: result.error_details) ]
    end
  end
end
