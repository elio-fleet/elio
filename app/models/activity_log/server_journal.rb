# The journal of one server (its Journal tab and its export): its notes and
# its events on one timeline, newest first. Read from the query parameters:
# "show" keeps one part (notes, events, accesses and keys, deployments) and
# the Journal's search (text and period) applies to notes and events alike.
#
#   journal = ServerJournal.new(server, params)
#   entries, more = journal.page(2, per_page: 30) # ServerNote / Activity
class ServerJournal
  FILTERS = %w[notes events access deployments].freeze
  # Keys given, extended, expired or removed, and those seen or lost on the server.
  ACCESS_KINDS = (Activity.kinds_where { |kind| kind.category == :keys } + %w[unknown_key_detected key_disappeared ssh_access_lost]).freeze
  DEPLOYMENT_KINDS = %w[coolify_deployed coolify_deploy_failed].freeze

  attr_reader :server, :filter, :search

  def initialize(server, params)
    @server = server
    @filter = params[:show].presence_in(FILTERS)
    @search = JournalSearch.new(params)
  end

  def notes
    return ServerNote.none unless filter.nil? || filter == "notes"

    search.apply(server.notes.recent, ServerNote).includes(:user)
  end

  # The note itself is in the journal: not its "note added" activity as well.
  def events
    return Activity.none if filter == "notes"

    scope = Activity.recent.where(server: server).where.not(kind: "server_note_added")
    scope = scope.where(kind: ACCESS_KINDS) if filter == "access"
    scope = scope.where(kind: DEPLOYMENT_KINDS) if filter == "deployments"
    search.apply(scope, Activity).includes(:user, :server, :public_key)
  end

  # The entries of page `number` and whether older ones follow.
  def page(number, per_page:)
    limit = number * per_page
    entries = (notes.limit(limit + 1).to_a + events.limit(limit + 1).to_a).sort_by(&:created_at).reverse
    [ entries.drop(limit - per_page).first(per_page), entries.size > limit ]
  end

  # The "deployments" filter only for a server that had one.
  def deployments? = Activity.where(server: server, kind: DEPLOYMENT_KINDS).exists?

  def filtered? = filter.present? || search.any?

  # The query parameters to keep in a link (pagination, export).
  def to_params = { show: filter, **search.to_params }.compact
end
