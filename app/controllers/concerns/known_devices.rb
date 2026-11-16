# Recognizes the browsers an account already signed in from, and emails its
# owner when a sign in comes from a new one: if it was not them, someone has
# their password. The browser keeps an encrypted cookie listing the accounts
# that signed in from it; nothing is stored on the server.
#
# Called once the sign in really completes (after the second factor), so the
# page answers the same whether an email is sent or not.
module KnownDevices
  COOKIE = :elio_devices
  LIMIT = 20 # accounts remembered per browser

  private

  # alert: false when another email already tells about this sign in.
  def note_sign_in_device(user, alert: true)
    known = known_device_user_ids
    return if known.include?(user.id)

    cookies.encrypted.permanent[COOKIE] = { value: (known + [ user.id ]).last(LIMIT), httponly: true, same_site: :lax }
    # The very first sign in of an account (invitation, setup) has no older device to compare with.
    return unless alert && user.sign_in_count > 1 && Rails.configuration.x.mail_enabled

    AccountMailer.new_device_sign_in(user, ip: request.remote_ip, at: Time.current, browser: request.user_agent.to_s.truncate(200)).deliver_later
  end

  def known_device_user_ids
    Array(cookies.encrypted[COOKIE]).grep(Integer)
  end
end
