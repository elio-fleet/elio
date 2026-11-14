# First launch: creates the first admin account, then disappears.
class SetupsController < ApplicationController
  layout "auth"

  SETUP_LOCK = 0x456c696f # "Elio": PostgreSQL advisory lock key

  skip_before_action :require_setup, :authenticate_user!, :authorize_view!
  before_action { raise ActionController::RoutingError, "Setup already done" if User.exists? }
  throttle only: :create, to: 5, within: 1.minute, redirect: :new_setup_path

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[email password password_confirmation]).merge(role: :admin))
    unless setup_token_valid?
      @user.errors.add(:base, t("flash.setups.wrong_token"))
      return render :new, status: :unprocessable_entity
    end

    if create_first_admin
      sign_in(@user)
      redirect_to root_path, notice: t("flash.setups.welcome")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # With ELIO_SETUP_TOKEN set (recommended in production), the first account
  # needs it: otherwise whoever reaches a fresh installation first becomes admin.
  def setup_token_valid?
    expected = ENV["ELIO_SETUP_TOKEN"].to_s
    expected.empty? || ActiveSupport::SecurityUtils.secure_compare(params[:setup_token].to_s, expected)
  end

  # Under a lock: two simultaneous submissions cannot both create an admin.
  def create_first_admin
    User.transaction do
      User.connection.execute(User.sanitize_sql_array([ "SELECT pg_advisory_xact_lock(?)", SETUP_LOCK ]))
      raise ActionController::RoutingError, "Setup already done" if User.exists?

      # The language the first admin set up Elio in becomes the language of the
      # installation (emails, runs, channels without their own language).
      @user.save && AppSetting.current.update!(default_locale: I18n.locale.to_s)
    end
  end
end
