module Settings
  # The addresses allowed to reach SSH (SshSource), in the "Suggested firewall
  # rules" card of the general settings: add, remove, reorder.
  class SshSourcesController < ApplicationController
    require_permission :administer

    def create
      source = SshSource.new(params.expect(ssh_source: %i[name cidr]).merge(position: SshSource.maximum(:position).to_i + 1))
      if source.save
        redirect_to settings_firewall_path, notice: t("ssh_sources_controller.created", name: source.name)
      else
        redirect_to settings_firewall_path, alert: source.errors.full_messages.to_sentence
      end
    end

    def destroy
      source = SshSource.find(params[:id])
      source.destroy!
      ServerGroup.where("ssh_source_ids @> ?", [ source.id ].to_json).find_each do |group|
        group.update_columns(ssh_source_ids: group.ssh_source_ids - [ source.id ])
      end
      redirect_to settings_firewall_path, notice: t("ssh_sources_controller.deleted", name: source.name), status: :see_other
    end

    def move
      SshSource.find(params[:id]).move!(params[:direction] == "up" ? -1 : 1)
      redirect_to settings_firewall_path, status: :see_other
    end
  end
end
