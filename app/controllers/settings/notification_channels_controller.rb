module Settings
  class NotificationChannelsController < ApplicationController
    require_permission :administer

    before_action :set_channel, only: %i[edit update destroy test]

    # New channels receive the warnings and critical activities by default.
    def new
      @channel = NotificationChannel.new(activity_kinds: Activity::KINDS.values.reject { |kind| kind.severity == :info }.map { |kind| kind.key.to_s })
    end

    def create
      @channel = NotificationChannel.new(channel_params)

      if @channel.save
        redirect_to settings_notifications_path, notice: t("notification_channels_controller.created", channel_name: @channel.name)
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    # A blank webhook keeps the current one (it is never sent back to the browser).
    def update
      attributes = channel_params
      attributes.delete(:webhook_url) if attributes[:webhook_url].blank?

      if @channel.update(attributes)
        redirect_to settings_notifications_path, notice: t("notification_channels_controller.updated", channel_name: @channel.name)
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @channel.destroy!
      redirect_to settings_notifications_path, notice: t("notification_channels_controller.deleted", channel_name: @channel.name), status: :see_other
    end

    def test
      @channel.in_language { @channel.notifier.deliver_test(@channel) }
      @channel.record_delivery!
      redirect_to settings_notifications_path, notice: t("notification_channels_controller.test_sent", channel_name: @channel.name)
    rescue Notifications::DeliveryError => e
      @channel.record_delivery!(error: e.message)
      redirect_to settings_notifications_path, alert: t("notification_channels_controller.test_failed", channel_name: @channel.name, message: e.message)
    end

    private

    def set_channel
      @channel = NotificationChannel.find(params[:id])
    end

    def channel_params
      params.expect(notification_channel: [ :name, :kind, :locale, :webhook_url, :recipients, :mention_channel, :daily_digest, :group_minutes, :enabled, activity_kinds: [] ])
    end
  end
end
