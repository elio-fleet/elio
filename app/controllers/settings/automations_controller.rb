module Settings
  class AutomationsController < ApplicationController
    require_permission :administer

    before_action :set_automation, only: %i[update run]

    def index
      @automations = Automation.available
      @groups = ServerGroup.order(:name)
    end

    def update
      if @automation.update(automation_params)
        state = @automation.enabled? ? t("automations_controller.enabled", interval_label: (Automation.interval_label(@automation.interval_minutes).downcase), downcase_first: @automation.scope_label.downcase_first) : t("automations_controller.disabled")
        redirect_to settings_automations_path, notice: t("automations_controller.saved", label: @automation.label, state: state)
      else
        redirect_to settings_automations_path, alert: @automation.errors.full_messages.to_sentence
      end
    end

    # The one Save of the page: every automation at once (automations[<id>][…]).
    def update_all
      automations = Automation.available.index_by { |automation| automation.id.to_s }
      errors = []
      Automation.transaction do
        params.fetch(:automations, {}).each do |id, values|
          automation = automations[id] or next
          next if automation.update(values.permit(:enabled, :interval_minutes, server_group_ids: []))

          errors << "#{automation.label} — #{automation.errors.full_messages.to_sentence}"
        end
        raise ActiveRecord::Rollback if errors.any?
      end
      if errors.any?
        redirect_to settings_automations_path, alert: errors.to_sentence, status: :see_other
      else
        redirect_to settings_automations_path, notice: t("automations_controller.saved_all"), status: :see_other
      end
    end

    def run
      task, started = @automation.start_now!(user: current_user)
      redirect_to task_path(task), notice: started ? t("automations_controller.started", label: @automation.label) : t("flash.already_running")
    end

    private

    def set_automation
      @automation = Automation.find(params[:id])
    end

    def automation_params
      params.expect(automation: [ :enabled, :interval_minutes, server_group_ids: [] ])
    end
  end
end
