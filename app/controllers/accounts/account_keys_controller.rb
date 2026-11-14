# "My SSH keys" on the account page: the signed-in user says which keys of
# the keyring are theirs (a person's key nobody owns yet), or that one is not.
# Used by "Add my key temporarily" on the server page.
class AccountKeysController < ApplicationController
  require_permission :operate

  def create
    public_key = PublicKey.of_kind("person").unowned.find(params.expect(:public_key_id))
    public_key.update!(user: current_user)
    Activity.record!(:public_key_owner_changed, public_key: public_key, fingerprint: public_key.fingerprint, owner: current_user.email)
    redirect_to account_path(anchor: "my-keys"), notice: t("account_keys_controller.claimed", name: public_key.name), status: :see_other
  end

  def destroy
    public_key = current_user.public_keys.find(params[:id])
    public_key.update!(user: nil)
    Activity.record!(:public_key_owner_changed, public_key: public_key, fingerprint: public_key.fingerprint, owner: nil)
    redirect_to account_path(anchor: "my-keys"), notice: t("account_keys_controller.released", name: public_key.name), status: :see_other
  end
end
