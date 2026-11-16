module Users
  # Sign in, with a second step (TwoFactorChallengesController) for accounts
  # that enabled 2FA: the password alone never opens a session for them.
  class SessionsController < Devise::SessionsController
    include Throttled
    include KnownDevices

    throttle only: :create, to: 20, within: 5.minutes, redirect: :new_user_session_path # (above the per-account lock: 10)

    def create
      # Check the password without opening a session nor counting a sign in
      # (trackable): that happens once the sign in really completes.
      request.env["devise.skip_trackable"] = true
      user = warden.authenticate!(auth_options.merge(store: false))

      if user.two_factor_enabled?
        sign_out(:user) # never leave a session open before the second factor
        session[:two_factor] = { "user_id" => user.id, "remember" => params.dig(:user, :remember_me) == "1", "started_at" => Time.current.to_i }
        redirect_to new_two_factor_challenge_path
      else
        user.update_tracked_fields!(request)
        set_flash_message!(:notice, :signed_in)
        # force: authenticate!(store: false) left the user in Warden for this
        # request, so without it Devise would think they are signed in already.
        sign_in(resource_name, user, force: true)
        note_sign_in_device(user)
        respond_with user, location: after_sign_in_path_for(user)
      end
    end
  end
end
