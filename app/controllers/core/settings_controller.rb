class SettingsController < ApplicationController
  require_permission :administer

  THRESHOLDS = Settings::HealthThresholdsController::FIELDS

  def show
    @ssh_key = SshKey.current
    @rotation = KeyRotation.in_progress
  end

  # The one Save of the General page: default language, health thresholds and
  # prompt instructions together. Changed thresholds recompute every health.
  def update
    setting = AppSetting.current
    setting.assign_attributes(params.expect(app_setting: [ :default_locale, *THRESHOLDS ]))
    if params.key?(:prompt_instructions)
      setting.prompt_instructions_form = params.permit(prompt_instructions: AppSetting::PROMPT_KINDS)[:prompt_instructions]&.to_h || {}
    end
    thresholds_changed = (setting.changed & THRESHOLDS.map(&:to_s)).any?

    if setting.save
      Server.find_each(&:refresh_health!) if thresholds_changed
      redirect_to settings_path, notice: t("settings_controller.saved")
    else
      redirect_to settings_path, alert: setting.errors.full_messages.to_sentence
    end
  end
end
