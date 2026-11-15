module Settings
  # Dry run of a rotation of Elio's key (read-only checks on every server),
  # followed as a task, so the servers that would fail are fixed beforehand.
  class KeyRotationChecksController < ApplicationController
    require_permission :administer

    def create
      servers = Server.order(:name).to_a
      label = LocalizedText.part("key_rotation_checks_controller.label", t: LocalizedText.part("count.servers", count: servers.size))
      task = BackgroundTask.enqueue!(kind: "key_rotation_check", label: label, servers: servers) do |item|
        CheckKeyRotationJob.perform_later(item.server, task_item: item)
      end

      redirect_to task_path(task), notice: t("key_rotation_checks_controller.started")
    end
  end
end
