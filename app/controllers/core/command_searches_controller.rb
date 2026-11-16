# What the quick search (⌘K) cannot know from the page: the CVEs, the
# packages and the server notes that match the typed text (GET /search?q=,
# JSON), a few of each, read by command_palette_controller.js while typing.
class CommandSearchesController < ApplicationController
  PER_GROUP = 5
  MIN_LENGTH = 2
  CVE_ID = /\ACVE-\d{4}-\d{4,}\z/i
  # "CVE-2024", "cve-2024-38", "2024-3800": a CVE is looked for (in the big
  # table of the fleet's CVEs) instead of a package.
  CVE_FRAGMENT = /\A(CVE-?\d|\d{4}-\d)/i

  def index
    query = params[:q].to_s.squish.first(JournalSearch::MAX_LENGTH)
    results = if query.length < MIN_LENGTH then []
    elsif query.match?(CVE_FRAGMENT) then cves(query) + notes(query)
    else packages(query) + notes(query)
    end
    render json: { results: results }
  end

  private

  # The fleet's CVEs whose id contains the text, with their number of
  # servers; an exact id known only from the feeds (or the score providers)
  # as well.
  def cves(query)
    counts = ServerVulnerability.where("server_vulnerabilities.cve ILIKE ?", JournalSearch.like(query))
                                .group(:cve).order(:cve).limit(PER_GROUP).distinct.count(:server_id)
    cve = query.upcase
    if counts.empty? && cve.match?(CVE_ID) && (Vulnerability.exists?(cve: cve) || CveScore.exists?(cve: cve))
      return [ result(:cves, cve, t("command_searches_controller.cve_not_on_fleet"), vulnerability_path(cve)) ]
    end

    counts.map { |id, servers| result(:cves, id, t("command_searches_controller.servers", count: servers), vulnerability_path(id)) }
  end

  # The package names that contain the text, the exact name first, with their
  # number of servers; each opens the fleet package search on that name.
  def packages(query)
    counts = Inventory::Package.search(query).group(:name)
                               .order(Arel.sql("lower(inventory_packages.name) = #{Inventory::Package.connection.quote(query.downcase)} DESC"), :name)
                               .limit(PER_GROUP).distinct.count(:server_id)
    counts.map { |name, servers| result(:packages, name, t("command_searches_controller.servers", count: servers), packages_path(q: name)) }
  end

  # The latest notes whose text contains the words, under their server.
  def notes(query)
    ServerNote.where("server_notes.body ILIKE ?", JournalSearch.like(query)).recent.includes(:server).limit(PER_GROUP).map do |note|
      result(:notes, note.server.name, note.excerpt(80), server_path(note.server, tab: "journal", show: "notes"))
    end
  end

  def result(group, label, hint, url) = { group: t("command_searches_controller.groups.#{group}"), label: label, hint: hint, url: url }
end
