module Settings
  # Docker (admins): which alerts the containers and images raise, the
  # registry credentials for private images (never shown back), and the
  # registry check run now.
  class DockerController < ApplicationController
    require_permission :administer

    ALERTS = %i[docker_alert_unhealthy docker_alert_restarts docker_alert_updates docker_alert_vulnerabilities].freeze

    def show
      @setting = AppSetting.current
      @registries = ImageRegistry::UpdateCheck.credentials.keys
      @automation = Automation.all_kinds.find { |automation| automation.kind == "docker_image_updates" }
      @updates = ImageUpdate.order(checked_at: :desc).limit(200).to_a
    end

    def update
      setting = AppSetting.current
      attributes = params.expect(app_setting: [ *ALERTS, :docker_registry_credentials ])
      credentials = attributes.delete(:docker_registry_credentials)
      attributes[:docker_registry_credentials] = credentials.strip.presence if credentials.present?
      attributes[:docker_registry_credentials] = nil if params[:clear_credentials] == "1"
      if (errors = credential_errors(attributes[:docker_registry_credentials])).any?
        return redirect_to(settings_docker_path, alert: t("docker_controller.credentials_refused", errors_to_sentence: errors.to_sentence))
      end

      setting.update!(attributes)
      Server.where(id: Inventory::Snapshot.where(category: "docker").select(:server_id)).find_each(&:refresh_health!)
      redirect_to settings_docker_path, notice: t("docker_controller.saved")
    end

    def check
      automation = Automation.all_kinds.find { |candidate| candidate.kind == "docker_image_updates" }
      task, started = automation.start_now!(user: current_user)
      redirect_to task_path(task), notice: started ? t("docker_controller.check_started") : t("flash.already_running")
    end

    private

    # One "registry user token" per line, a registry host first.
    def credential_errors(text)
      text.to_s.lines.each_with_index.filter_map do |line, index|
        next if line.strip.empty?

        registry, user, token, extra = line.split
        "ligne #{index + 1} (attendu : registre utilisateur jeton)" if token.nil? || extra || !registry.match?(/\A[a-z0-9.-]+(:\d+)?\z/i) || user.blank?
      end
    end
  end
end
