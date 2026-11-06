module Settings
  # Instructions of the administrator added at the end of the prompts for an
  # AI (ServerPrompt), one text per prompt.
  class PromptInstructionsController < ApplicationController
    require_permission :administer

    def update
      setting = AppSetting.current
      setting.prompt_instructions_form = params.fetch(:prompt_instructions, {}).permit(*AppSetting::PROMPT_KINDS).to_h
      if setting.save
        redirect_to settings_path(anchor: "prompt-instructions"), notice: t("prompt_instructions_controller.saved")
      else
        redirect_to settings_path(anchor: "prompt-instructions"), alert: setting.errors.full_messages.to_sentence
      end
    end
  end
end
