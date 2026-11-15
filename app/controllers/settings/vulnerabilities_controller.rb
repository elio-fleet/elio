module Settings
  # Vulnerability feeds (admins): state of each feed, update now, import a
  # file by hand (closed networks), and from which severity a fixable CVE
  # raises an alert.
  class VulnerabilitiesController < ApplicationController
    require_permission :administer

    MAX_IMPORT = 1.gigabyte
    IMPORT_DIR = Rails.root.join("storage", "vulnerabilities")

    def show
      @feeds = Vulnerability::SOURCES.keys.map { |source| VulnerabilityFeed.for(source) }
      @usage = Vulnerabilities.usage
      @automation = Automation.all_kinds.find { |automation| automation.kind == "vulnerabilities_update" }
      @setting = AppSetting.current
      @providers = ScoreProvider.all_providers
      @coverage = CveScore.scored.group(:provider_key).count
      @fleet_cves = Vulnerabilities::Scores.fleet_cves.size
      @scores_automation = Automation.all_kinds.find { |automation| automation.kind == "cve_scores_update" }
    end

    # Asks the score providers now (the automation, run once).
    def scores
      automation = Automation.all_kinds.find { |candidate| candidate.kind == "cve_scores_update" }
      task, started = automation.start_now!(user: current_user)
      redirect_to task_path(task), notice: started ? t("vulnerabilities_controller.scores_started") : t("flash.already_running")
    end

    def update
      setting = AppSetting.current
      attributes = params.expect(app_setting: [ :vulnerability_alert_severity, score_bands_form: {} ])
      if setting.update(attributes)
        Server.find_each(&:refresh_health!) if setting.saved_change_to_vulnerability_alert_severity?
        redirect_to settings_vulnerabilities_path(anchor: (attributes.key?(:score_bands_form) ? "score-colors" : nil)),
                    notice: attributes.key?(:score_bands_form) ? t("vulnerabilities_controller.colors_saved") : t("vulnerabilities_controller.alerts_saved")
      else
        redirect_to settings_vulnerabilities_path, alert: setting.errors.full_messages.to_sentence
      end
    end

    # Downloads the feeds now (the daily automation, run once).
    def refresh
      automation = Automation.all_kinds.find { |candidate| candidate.kind == "vulnerabilities_update" }
      task, started = automation.start_now!(user: current_user)
      redirect_to task_path(task), notice: started ? t("vulnerabilities_controller.refresh_started") : t("flash.already_running")
    end

    # A Debian Security Tracker JSON or an Ubuntu OSV zip, recognized by its content.
    def import
      file = params[:file]
      return redirect_to(settings_vulnerabilities_path, alert: t("vulnerabilities_controller.choose_file")) unless file.respond_to?(:path)
      return redirect_to(settings_vulnerabilities_path, alert: t("vulnerabilities_controller.too_large")) if file.size > MAX_IMPORT

      source = Vulnerabilities::Update.detect(file.path)
      return redirect_to(settings_vulnerabilities_path, alert: t("vulnerabilities_controller.not_recognized")) unless source

      FileUtils.mkdir_p(IMPORT_DIR)
      path = IMPORT_DIR.join("import-#{SecureRandom.hex(8)}")
      FileUtils.cp(file.path, path)
      label = LocalizedText.part("vulnerabilities_controller.import_label", fetch: Vulnerability::SOURCES.fetch(source))
      task = BackgroundTask.enqueue!(kind: "vulnerabilities", label: label, servers: [], user: current_user)
      ImportVulnerabilitiesJob.perform_later(source, path.to_s, task)
      redirect_to task_path(task), notice: t("vulnerabilities_controller.import_started", fetch: (Vulnerability::SOURCES.fetch(source)))
    end
  end
end
