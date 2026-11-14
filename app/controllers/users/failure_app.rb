module Users
  # Devise's answer to a failed sign in, with the lock rule in its messages
  # ("after 10 failed attempts, an account is locked for 15 minutes"): the
  # same text for every email, so it tells nothing about which accounts exist.
  class FailureApp < Devise::FailureApp
    protected

    def i18n_options(options)
      super.merge(maximum_attempts: User.maximum_attempts, duration: User.lock_duration)
    end
  end
end
