module Settings
  # The "Firewall" tab of the settings: what Elio suggests in the Firewall
  # tab of the servers (options, sources allowed to reach SSH).
  class FirewallsController < ApplicationController
    require_permission :administer

    def show
    end
  end
end
