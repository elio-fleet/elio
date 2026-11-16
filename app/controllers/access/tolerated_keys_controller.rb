# Tolerating a key outside the keyring, with a reason (ToleratedKey), from the
# "Outside the keyring" list, and tolerating it no longer.
class ToleratedKeysController < ApplicationController
  require_permission :operate

  def create
    tolerated = ToleratedKey.new(params.expect(tolerated_key: %i[fingerprint name reason]).merge(user: Current.user))
    if tolerated.save
      Activity.record!(:key_tolerated, key_name: tolerated.name, fingerprint: tolerated.fingerprint, reason: tolerated.reason)
      redirect_to public_keys_path(kind: "outside"), notice: t("tolerated_keys_controller.created", name: key_label(tolerated)), status: :see_other
    else
      redirect_to public_keys_path(kind: "outside"), alert: t("tolerated_keys_controller.not_saved", errors: tolerated.errors.full_messages.to_sentence), status: :see_other
    end
  end

  def destroy
    tolerated = ToleratedKey.find(params[:id])
    tolerated.destroy!
    Activity.record!(:key_tolerance_removed, key_name: tolerated.name, fingerprint: tolerated.fingerprint)
    redirect_to public_keys_path(kind: "outside"), notice: t("tolerated_keys_controller.deleted", name: key_label(tolerated)), status: :see_other
  end

  private

  def key_label(tolerated) = tolerated.name || tolerated.fingerprint
end
