# Health reasons are stored as translation keys with their parameters
# ({ "key", "params" }); servers of an older version still have French
# sentences ({ "text" }). Computes them again from the inventory already
# stored (no SSH). Kept as the last migration of the release on purpose: it
# runs the application's code, which needs every column of the release.
class RefreshHealthReasonsAfterUpgrade < ActiveRecord::Migration[8.1]
  def up
    Server.reset_column_information
    AppSetting.reset_column_information
    say_with_time "health reasons of #{Server.count} servers" do
      Server.find_each do |server|
        server.refresh_health!
      rescue StandardError => e
        say "#{server.name}: #{e.class}: #{e.message}", true
      end
    end
  end

  def down
    # Nothing to undo: older versions read the new reasons as unknown.
  end
end
