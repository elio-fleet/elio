# Health reasons were stored as French sentences ({ "text" }); they are now
# translation keys with their parameters ({ "key", "params" }), written in
# the reader's language. Computes them again from the inventory already
# stored (no SSH): the state does not change, only how reasons are stored.
class RefreshHealthReasons < ActiveRecord::Migration[8.1]
  # Moved to RefreshHealthReasonsAfterUpgrade: computing the health here runs
  # the code of the release before the migrations that follow (columns read by
  # the DNS health did not exist yet, every server failed).
  def up
  end

  def down
    # Nothing to undo: older versions read the new reasons as unknown.
  end
end
