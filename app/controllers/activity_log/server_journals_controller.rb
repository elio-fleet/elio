# The journal of one server exported as .csv / .json for an audit: its
# events and its notes, with the filter and the search of its Journal tab
# (ServerJournal). The page itself is the server's Journal tab.
class ServerJournalsController < ApplicationController
  def show
    server = Server.find(params[:server_id])
    journal = ServerJournal.new(server, params)
    respond_to do |format|
      format.html { redirect_to server_path(server, tab: "journal", **journal.to_params) }
      format.csv { export(journal, :csv) }
      format.json { export(journal, :json) }
    end
  end

  private

  def export(journal, format)
    export = ServerJournalExport.new(journal, url: ->(activity) { activity_url(activity) },
                                              note_url: ->(note) { server_url(journal.server, tab: "journal", anchor: helpers.dom_id(note)) })
    send_data format == :csv ? export.to_csv : export.to_json, filename: export.filename(format), type: format, disposition: "attachment"
  end
end
