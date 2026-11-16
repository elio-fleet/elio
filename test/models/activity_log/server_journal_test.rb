require "test_helper"
require "csv"

class ServerJournalTest < ActiveSupport::TestCase
  setup do
    @server = servers(:web)
    travel_to(4.minutes.ago) { @note = @server.notes.create!(body: "Moved the **backups** to the new disk", user: users(:operator)) }
    travel_to(3.minutes.ago) { @key = Activity.record!(:key_added, server: @server, public_key: public_keys(:alice), unix_user: "deploy") }
    travel_to(2.minutes.ago) { @deployed = Activity.record!(:coolify_deployed, server: @server, application: "shop", commit: "abc1234") }
    travel_to(1.minute.ago) { @port = Activity.record!(:port_opened, server: @server, port: 8081, protocol: "tcp") }
    Activity.record!(:server_note_added, server: @server, excerpt: "Moved the backups")
    Activity.record!(:key_added, server: servers(:db), public_key: public_keys(:alice), unix_user: "admin")
  end

  def entries(**params) = ServerJournal.new(@server, params).page(1, per_page: 10).first

  test "its notes and its events on one timeline, newest first, without the note's own activity" do
    assert_equal [ @port, @deployed, @key, @note ], entries
  end

  test "keeps the notes, the events, the accesses and keys or the deployments only" do
    assert_equal [ @note ], entries(show: "notes")
    assert_equal [ @port, @deployed, @key ], entries(show: "events")
    assert_equal [ @key ], entries(show: "access")
    assert_equal [ @deployed ], entries(show: "deployments")
    assert_equal [ @port, @deployed, @key, @note ], entries(show: "nope")
  end

  test "temporary accesses, their extension and their expiry are accesses" do
    expired = Activity.record!(:key_expired, server: @server, public_key: public_keys(:alice), unix_user: "deploy", user: nil)
    unknown = Activity.record!(:unknown_key_detected, server: @server, unix_user: "deploy", key_name: "laptop")

    assert_equal [ unknown, expired, @key ], entries(show: "access")
  end

  test "the search reads the notes and the events, with the filter" do
    assert_equal [ @note ], entries(q: "backups")
    assert_equal [ @note ], entries(q: "operator@")
    assert_equal [ @key ], entries(q: "alice")
    assert_empty entries(q: "backups", show: "events")
    assert_equal [ @port, @deployed, @key, @note ], entries(from: Date.current.iso8601)
    assert ServerJournal.new(@server, q: "x").filtered?
    assert_not ServerJournal.new(@server, {}).filtered?
  end

  test "a page says whether older entries follow" do
    journal = ServerJournal.new(@server, {})

    assert_equal [ [ @port, @deployed ], true ], journal.page(1, per_page: 2)
    assert_equal [ [ @key, @note ], false ], journal.page(2, per_page: 2)
  end

  test "the deployments filter only for a server that had one" do
    assert ServerJournal.new(@server, {}).deployments?
    assert_not ServerJournal.new(servers(:db), {}).deployments?
  end

  test "the export: the notes on the columns of the events, newest first, with the filter and the search" do
    export = ServerJournalExport.new(ServerJournal.new(@server, q: "o", show: nil), url: ->(activity) { "/journal/#{activity.id}" },
                                                                                    note_url: ->(note) { "/note/#{note.id}" })

    rows = CSV.parse(export.to_csv)
    assert_equal ActivityExport::HEADERS, rows.first
    note = ActivityExport::HEADERS.zip(rows.last).to_h
    assert_equal [ "server_note", "Note", "Moved the **backups** to the new disk", "Web", "operator@example.com", "/note/#{@note.id}" ],
                 note.values_at("kind", "label", "summary", "server", "author", "url")
    assert_equal({ "server" => "Web", "q" => "o" }, JSON.parse(export.to_json)["filters"])
    assert_equal %w[port_opened coolify_deployed key_added server_note], export.records.pluck("kind")
    assert_match(/\Aelio-journal-web-\d{4}-\d{2}-\d{2}\.json\z/, export.filename(:json))
  end

  test "the export is cut at its limit, notes and events together" do
    cut = ServerJournalExport.new(ServerJournal.new(@server, {}), limit: 3)
    assert_equal %w[port_opened coolify_deployed key_added], cut.records.pluck("kind")
    assert cut.truncated?

    assert_not ServerJournalExport.new(ServerJournal.new(@server, {}), limit: 4).truncated?
  end
end
