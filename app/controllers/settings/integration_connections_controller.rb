module Settings
  # Settings → Extensions → an extension with several connections (Coolify:
  # one per team or instance): add, change, test and remove each one (admins).
  # Secrets are never sent back; a blank secret keeps the stored one.
  class IntegrationConnectionsController < ApplicationController
    require_permission :administer

    before_action :set_integration
    before_action :set_connection, only: %i[edit update destroy]

    def new
      @connection = @integration.connections.build
    end

    def create
      @connection = @integration.connections.build(name: name_param)
      @connection.assign_form(form_values)
      if @connection.save
        Activity.record!(:integration_connection_added, integration: @integration.kind, integration_label: @integration.label, connection: @connection.label)
        @integration.enqueue_sync! if @integration.enabled?
        redirect_to edit_settings_integration_path(@integration.kind), notice: wording("integration_connections_controller.created", label: @connection.label)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      @connection.name = name_param
      @connection.assign_form(form_values)
      if @connection.save
        @integration.enqueue_sync! if @integration.enabled?
        redirect_to edit_settings_integration_path(@integration.kind), notice: wording("integration_connections_controller.updated", label: @connection.label)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      label = @connection.label
      @connection.destroy!
      Activity.record!(:integration_connection_removed, integration: @integration.kind, integration_label: @integration.label, connection: label)
      redirect_to edit_settings_integration_path(@integration.kind), notice: wording("integration_connections_controller.deleted", label: label), status: :see_other
    end

    # Tries the values of the form (a new connection or a saved one), without saving them.
    def test
      @connection = params[:id] ? @integration.connections.find(params[:id]) : @integration.connections.build
      @connection.name = name_param
      @connection.assign_form(form_values)
      @test_result = begin
        [ :good, @integration.definition.test_connection(@connection) ]
      rescue Integrations::Error => e
        [ :crit, e.message ]
      end

      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("integration-test-result", partial: "settings/integrations/test_result", locals: { result: @test_result, kind: @integration.kind }) }
        format.html { render(@connection.persisted? ? :edit : :new) }
      end
    end

    private

    def set_integration
      definition = Integration.definitions[params[:integration_kind].to_s]
      raise ActiveRecord::RecordNotFound unless definition&.multiple_connections?

      @integration = Integration.find_or_create_by!(kind: params[:integration_kind])
    end

    def set_connection
      @connection = @integration.connections.find(params[:id])
    end

    def name_param = params.dig(:connection, :name).to_s

    def wording(key, **options) = helpers.integration_text(@integration.kind, key, **options)

    def form_values
      values = params.dig(:connection, :values)
      return {} unless values

      keys = @integration.definition.connection_fields.map { |field| field.type == :checkboxes ? { field.key => [] } : field.key }
      values.permit(*keys).to_h
    end
  end
end
