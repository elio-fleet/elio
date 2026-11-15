module Settings
  # Settings → Extensions (admins): enable, configure, test and synchronize
  # each extension (see Integration). Secrets are never sent back.
  class IntegrationsController < ApplicationController
    require_permission :administer

    before_action :set_integration, except: :index

    def index
      @integrations = Integration.all_kinds
    end

    def edit
    end

    def update
      was_enabled = @integration.enabled?
      @integration.assign_form(form_values)
      @integration.enabled = params.dig(:integration, :enabled) == "1"

      if @integration.save
        if @integration.enabled? != was_enabled
          Activity.record!(@integration.enabled? ? :integration_enabled : :integration_disabled, integration: @integration.kind, integration_label: @integration.label)
        end
        task = @integration.enqueue_sync! if @integration.enabled? && !was_enabled
        notice = @integration.enabled? ? t(task ? "integrations_controller.saved_enabled" : "integrations_controller.saved", label: @integration.label) : t("integrations_controller.saved_off", label: @integration.label)
        redirect_to edit_settings_integration_path(@integration.kind), notice: notice
      else
        render :edit, status: :unprocessable_entity
      end
    end

    # Tries the connection with the values of the form, without saving them.
    def test
      @integration.assign_form(form_values)
      @test_result = begin
        [ :good, @integration.definition.test_connection(@integration) ]
      rescue Integrations::Error => e
        [ :crit, e.message ]
      end

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("integration-test-result", partial: "settings/integrations/test_result", locals: { result: @test_result }) }
        format.html { render :edit }
      end
    end

    def sync
      unless @integration.enabled?
        return redirect_to edit_settings_integration_path(@integration.kind), alert: t("integrations_controller.turn_on_first")
      end

      redirect_to task_path(@integration.enqueue_sync!), notice: t("integrations_controller.sync_started", label: @integration.label)
    end

    # Deletes what a turned off extension read from its service (confirmed, logged).
    def purge
      if @integration.purge_data!
        redirect_to edit_settings_integration_path(@integration.kind), notice: t("integrations_controller.data_deleted", label: @integration.label), status: :see_other
      else
        redirect_to edit_settings_integration_path(@integration.kind), alert: t("integrations_controller.turn_off_first"), status: :see_other
      end
    end

    private

    def set_integration
      raise ActiveRecord::RecordNotFound unless Integration.registry.key?(params[:kind])

      @integration = Integration.find_or_create_by!(kind: params[:kind])
    end

    def form_values
      values = params.dig(:integration, :values)
      return {} unless values

      keys = @integration.fields.map { |field| field.type == :checkboxes ? { field.key => [] } : field.key }
      values.permit(*keys).to_h
    end
  end
end
