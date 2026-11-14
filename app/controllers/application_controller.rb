class ApplicationController < ActionController::Base
  # Set once a first account exists (see require_setup); reset by the tests.
  class_attribute :setup_done, default: false, instance_accessor: false
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :switch_locale
  before_action :require_setup
  before_action :authenticate_user!, unless: :devise_controller?
  # Not in Devise controllers: during the sign in, current_user would
  # authenticate (and store) the user from the form before the 2FA step.
  before_action :set_current_user, unless: :devise_controller?
  before_action :require_two_factor_setup, unless: :devise_controller?
  include Authorization
  include Throttled

  layout :layout_by_resource

  private

  # The user's language, else the browser's, else the instance's.
  def switch_locale(&action)
    I18n.with_locale(request_locale, &action)
  end

  def request_locale
    # The session only (warden.user runs no strategy): in Devise
    # controllers, current_user would sign in from the form.
    Elio::Locales.find(warden.user(:user)&.locale) ||
      Elio::Locales.from_accept_language(request.headers["Accept-Language"]) ||
      Elio::Locales.find(AppSetting.current.default_locale) ||
      I18n.default_locale
  end

  # One page of a list (?page=), see Paginator and shared/_pagination.
  def paginate(collection, per_page:)
    Paginator.new(collection, page: params[:page], per_page: per_page)
  end

  def set_current_user
    Current.user = current_user
  end

  # Admins and operators must enable 2FA first when the settings require it:
  # straight to the setup page, which says why.
  def require_two_factor_setup
    return unless current_user&.two_factor_required?

    redirect_to main_app.new_two_factor_path
  end

  # Until the first admin exists, every page leads to the setup page. Once
  # there is a user there always will be (accounts are deactivated, never
  # deleted), so the check stops querying the database (AUDIT.md D13).
  def require_setup
    return if ApplicationController.setup_done

    if User.exists?
      ApplicationController.setup_done = true
    else
      redirect_to main_app.new_setup_path
    end
  end

  def layout_by_resource
    devise_controller? ? "auth" : "application"
  end
end
