# First launch: creates the first admin account, then disappears.
class SetupsController < ApplicationController
  layout "auth"

  SETUP_LOCK = 0x456c696f # "Elio": PostgreSQL advisory lock key

  skip_before_action :require_setup, :authenticate_user!, :authorize_view!
  before_action { raise ActionController::RoutingError, "Setup already done" if User.exists? }
  throttle only: :create, to: 5, within: 1.minute, redirect: :new_setup_path
  helper_method :chosen_locale, :address_warning, :installation_failures

  def new
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[email password password_confirmation]).merge(role: :admin, locale: chosen_locale&.to_s))
    unless setup_token_valid?
      @user.errors.add(:base, t("flash.setups.wrong_token"))
      return render :new, status: :unprocessable_entity
    end

    if create_first_admin
      sign_in(@user)
      # 2FA mandatory for admins (the default): straight to its setup page,
      # which says why, then to the overview and its getting started list.
      return redirect_to(new_two_factor_path) if @user.two_factor_required?

      redirect_to root_path, notice: t("flash.setups.welcome")
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  # The language picked on the page (?locale=), which comes before the
  # browser's: it becomes the first admin's and the installation's.
  def chosen_locale = Elio::Locales.find(params[:locale])

  def request_locale = chosen_locale || super

  # The links of the emails and notifications use ELIO_HOST: missing, or
  # another address than the one the page was opened at, they would not lead
  # back here. [:missing | :mismatch, params] or nil.
  def address_warning
    configured = ENV["ELIO_HOST"].to_s.strip
    actual = request.host_with_port
    return [ :missing, { variable: "ELIO_HOST", address: actual } ] if configured.empty?

    [ :mismatch, { variable: "ELIO_HOST", configured: configured, address: actual } ] unless configured.casecmp?(actual)
  end

  # What would break Elio right after the setup (a secret, a database):
  # the failures of bin/elio-doctor, without its network checks.
  def installation_failures
    @installation_failures ||= Installation::Doctor.new(network: false).call.select(&:failure?)
  end

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
