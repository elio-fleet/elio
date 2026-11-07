require "test_helper"

class ComponentsHelperTest < ActionView::TestCase
  include UiHelper
  include IconsHelper

  test "page_header: breadcrumb, title, badges, subtitle and the actions of the block" do
    render html: page_header("db-prod", subtitle: "admin@198.51.100.20", crumbs: [ [ "Serveurs", "/servers" ], "db-prod" ], badges: status_badge(:crit, "Critique")) { tag.a("Modifier", class: "btn") }

    assert_select "header.page-header nav.breadcrumbs a[href='/servers']", "Serveurs"
    assert_select "header.page-header nav.breadcrumbs span[aria-current=page]", "db-prod"
    assert_select "header.page-header h1.page-title", "db-prod"
    assert_select "header.page-header .badge", text: /Critique/
    assert_select "header.page-header .page-subtitle", "admin@198.51.100.20"
    assert_select "header.page-header .page-actions a.btn", "Modifier"
  end

  test "page_header without breadcrumb nor actions" do
    render html: page_header("Vue d'ensemble")

    assert_select "nav.breadcrumbs", 0
    assert_select ".page-actions", 0
    assert_select ".page-subtitle", 0
  end

  test "actions_menu: links, a button with a confirmation, the danger item in red" do
    render html: actions_menu { safe_join([ menu_item("Importer", "/import", icon: :arrow_up_circle), menu_separator,
                                              menu_item("Supprimer", "/servers/1", method: :delete, danger: true, confirm: "Supprimer ?") ]) }

    assert_select "details.actions-menu summary[aria-label=?]", I18n.t("ui.more_actions")
    assert_select "details.actions-menu a[role=menuitem][href='/import']", "Importer"
    assert_select "details.actions-menu [role=separator]"
    assert_select "details.actions-menu form[action='/servers/1'][data-turbo-confirm=?][data-confirm-variant=danger] button.text-crit-ink[role=menuitem]", "Supprimer ?", text: "Supprimer"
  end

  test "stat_tile with href is a link, marked when its filter is active" do
    render html: stat_tiles { safe_join([ stat_tile("Critiques", 2, href: "/servers?status=crit", active: true, tone: :crit), stat_tile("Total", 7) ]) }

    assert_select ".stat-tiles a.stat-tile[href=?][aria-current=true] .stat-value.text-crit-ink", "/servers?status=crit", text: "2"
    assert_select ".stat-tiles div.stat-tile .stat-value", "7"
  end

  test "filter_chip: active, count and dot" do
    render html: safe_join([ filter_chip("Tous", "/servers", active: true, count: 7), filter_chip("Production", "/servers?group=1", dot: "bg-red-500") ])

    assert_select "a.filter-chip[aria-current=true][href='/servers']", text: /Tous\s*7/
    assert_select "a.filter-chip[href=?] span.bg-red-500", "/servers?group=1"
    assert_select "a.filter-chip:not([aria-current])", 1
  end

  test "view_toggle marks the current view" do
    render html: view_toggle([ [ "list", "Liste", :list_bullet, "/servers" ], [ "grid", "Grille", :squares_2x2, "/servers?view=grid" ] ], current: "grid")

    assert_select ".view-toggle a[aria-current=true][data-view=grid]", "Grille"
    assert_select ".view-toggle a[data-view=list]:not([aria-current])", 1
  end

  test "tabs: current tab, coloured count, select for small screens and More menu" do
    render html: tabs([ { key: "overview", label: "Vue d'ensemble", path: "/s/1" }, { key: "vulnerabilities", label: "Vulnérabilités", path: "/s/1?tab=vulnerabilities", count: 51, tone: :crit } ],
                      current: "vulnerabilities", label: "Sections")

    assert_select "nav.tabs[aria-label=Sections][data-controller=overflow-tabs]"
    assert_select "nav.tabs a.tab[aria-current=page][data-tab=vulnerabilities] .tab-count.text-crit-ink", "51"
    assert_select "nav.tabs a.tab[data-tab=overview]:not([aria-current])"
    assert_select "nav.tabs select.tabs-select option[selected]", text: /Vulnérabilités/
    assert_select "nav.tabs details.tabs-more a[role=menuitem][hidden]", 2
  end

  test "panel: title, meta and link in the header" do
    render html: panel("Santé", meta: "il y a 9 min", link: [ "Graphiques", "/charts" ], id: "health") { tag.p("contenu") }

    assert_select "section#health.panel .card-header h2", "Santé"
    assert_select "section#health .card-header", text: /il y a 9 min/
    assert_select "section#health .card-header a[href='/charts']", "Graphiques"
    assert_select "section#health > p", "contenu"
  end

  test "fact_list skips missing values" do
    render html: fact_list([ [ "Noyau", "6.1.0" ], [ "Fuseau", nil ], [ "Démarré", "il y a 41 jours" ] ])

    assert_select "dl.fact-list dt", 2
    assert_select "dl.fact-list dd", "6.1.0"
  end

  test "attention_item: gravity, servers as chips, a named action" do
    render html: attention_list { attention_item(:crit, "Disque / à 94 %", servers: [ [ "db-prod", "/servers/1" ] ], action: [ "Voir le disque", "/servers/1#disks" ]) }

    assert_select "ul.attention-list li.attention-item[data-tone=crit]", text: /Disque \/ à 94 %/
    assert_select "li.attention-item a.server-chip[href='/servers/1']", "db-prod"
    assert_select "li.attention-item a.attention-action[href='/servers/1#disks']", text: /Voir le disque/
  end

  test "status_line, empty_state, timeline_item, group_tag and source_tag" do
    group = ServerGroup.new(name: "Production", color: "red")
    render html: safe_join([
      status_line([ { key: "ssh", label: "SSH", tone: :good, text: "OK" } ]) { "vérifié à l'instant" },
      empty_state("Aucun service", "Le compte n'en a pas.", icon: :cloud) { tag.a("Réglages", href: "/settings") },
      timeline { timeline_item("Une note", meta: "il y a 2 h", tone: :note, initials: "ON", note: "Migration le 20.") },
      group_tag(group), source_tag("Uptime Kuma")
    ])

    assert_select ".status-line [data-status=ssh] .badge", text: /OK/
    assert_select ".status-line", text: /vérifié à l'instant/
    assert_select ".empty-state p.font-medium", "Aucun service"
    assert_select ".empty-state a[href='/settings']"
    assert_select "ol.timeline li.timeline-item", text: /Une note/
    assert_select "li.timeline-item .prose-note", "Migration le 20."
    assert_select ".group-tag span.bg-red-500"
    assert_select ".group-tag", text: "Production"
    assert_select ".source-tag", "Uptime Kuma"
  end

  test "form_section: title and help, fields in the block" do
    render html: form_section("Seuils", "Au-delà…") { tag.input(name: "x") }

    assert_select "section.form-section h2", "Seuils"
    assert_select "section.form-section p", "Au-delà…"
    assert_select "section.form-section input[name=x]"
  end
end
