# The journal of one server for an audit (ServerJournal, with the filters of
# its tab): its events as in ActivityExport and its notes on the same
# columns (kind "server_note", the Markdown as summary), newest first, at
# most MAX_ROWS rows in all.
#
#   ServerJournalExport.new(ServerJournal.new(server, params), url: …, note_url: …).to_csv
class ServerJournalExport < ActivityExport
  # `url`: the permanent link of an activity; `note_url`: the link of a note.
  def initialize(journal, url: nil, note_url: nil, limit: MAX_ROWS)
    super(journal.events, filters: { server: journal.server.name, **journal.to_params }, url: url, limit: limit)
    @journal = journal
    @note_url = note_url
  end

  # Both lists are newest first: merged on the time (to the second), the event first in the same second.
  def records
    @journal_records ||= (super + note_records).each_with_index.sort_by { |record, index| [ -Time.iso8601(record["created_at"]).to_i, index ] }.map(&:first).first(@limit)
  end

  # The events and the notes each read one more than kept.
  def truncated? = ids.size + note_records.size > @limit

  def filename(extension) = "elio-journal-#{@journal.server.name.parameterize}-#{Date.current.iso8601}.#{extension}"

  private

  def note_records
    @note_records ||= @journal.notes.limit(@limit + 1).map do |note|
      { "id" => note.id, "created_at" => note.created_at.iso8601, "kind" => "server_note", "label" => I18n.t("activity.server_journal.note"),
        "category" => nil, "severity" => nil, "summary" => note.body, "server" => @journal.server.name, "author" => note.user&.email,
        "unix_user" => nil, "public_key" => nil, "url" => @note_url&.call(note) }
    end
  end
end
