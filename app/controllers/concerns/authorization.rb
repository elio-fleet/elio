# Role-based access (see User::PERMISSIONS). Every controller declares the
# permission its actions need; anything not declared requires :view.
#
#   require_permission :operate, only: %i[new create]
module Authorization
  extend ActiveSupport::Concern

  # Carries the permission that was missing (nil for a rule of its own, like
  # editing someone else's note), so the forbidden page names the roles it needs.
  class NotAuthorized < StandardError
    attr_reader :permission

    def initialize(permission = nil)
      @permission = permission
      super("not authorized#{": #{permission}" if permission}")
    end
  end

  included do
    before_action :authorize_view!, unless: :devise_controller?
    rescue_from NotAuthorized, with: :render_forbidden
    helper_method :can?
  end

  class_methods do
    def require_permission(permission, **options)
      before_action(-> { authorize!(permission) }, **options)
    end
  end

  private

  def can?(permission) = current_user&.can?(permission) || false

  def authorize_view! = authorize!(:view)

  def authorize!(permission)
    raise NotAuthorized.new(permission) unless can?(permission)
  end

  def render_forbidden(error = nil)
    message = forbidden_message(error&.permission)

    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message
        render turbo_stream: turbo_stream.update("flash", partial: "shared/flash"), status: :forbidden
      end
      format.html do
        if turbo_frame_request?
          render html: helpers.turbo_frame_tag(request.headers["Turbo-Frame"]) { helpers.tag.p(message, class: "forbidden py-4 text-sm text-crit-ink") }, status: :forbidden
        else
          render "errors/forbidden", locals: { message: message, back_path: forbidden_back_path }, status: :forbidden
        end
      end
      format.any { head :forbidden }
    end
  end

  def forbidden_message(permission)
    role = current_user.role_label
    return I18n.t("authorization.forbidden", role: role) unless User::PERMISSIONS.key?(permission)

    roles = User::PERMISSIONS.fetch(permission).map { |name| User.role_label(name) }
    I18n.t("authorization.forbidden_needs", role: role, roles: roles.join(" #{I18n.t("authorization.or")} "))
  end

  # The page the user came from, when it is one of ours and not this one.
  def forbidden_back_path
    referer = URI.parse(request.referer.to_s)
    return if referer.host != request.host || referer.path.blank? || referer.path == request.path

    referer.request_uri
  rescue URI::InvalidURIError
    nil
  end
end
