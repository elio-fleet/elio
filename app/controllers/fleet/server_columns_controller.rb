# The columns of the fleet list the signed-in user shows: a preference of
# their account (users.preferences), so it follows them to another browser.
# Back to the list as it was (its filters and order, even those of an
# instant search that changed the address since the page loaded).
class ServerColumnsController < ApplicationController
  def update
    shown = Array(params[:columns]).map(&:to_s)
    current_user.hide_fleet_columns!(User::FLEET_COLUMNS - shown)
    redirect_back_or_to servers_path, status: :see_other
  end
end
