import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Quick search over pages, actions, groups, servers (also by host name and
// IP, the `keywords`), keyring keys, and the tabs and inventory action of the
// servers (built here, listed once something is typed); the entries opened
// lately first (remembered in this browser). While typing, the CVEs, packages
// and server notes that match are asked to the server (data-search-url), and
// the last entries search the text: fleet packages, the journal, for a number
// the servers exposing that port, for a host name its DNS records.
// Opens with ⌘K / Ctrl+K or the sidebar button; arrows to move, Enter to
// open, Escape to close. An entry with `method: "post"` (an action) is sent
// as a form, so Turbo follows its redirection.
const RECENT_KEY = "elio-command-palette-recent"
const RECENT_MAX = 5
const SEARCH_DELAY = 200

export default class extends Controller {
  static targets = ["dialog", "input", "results", "empty", "items"]

  connect() {
    this.items = JSON.parse(this.itemsTarget.textContent)
    this.remote = []
    this.onKeydown = (event) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault()
        this.dialogTarget.open ? this.close() : this.open()
      }
    }
    document.addEventListener("keydown", this.onKeydown)
    this.dialogTarget.addEventListener("click", (event) => { if (event.target === this.dialogTarget) this.close() })
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    this.cancelSearch()
  }

  open() {
    this.inputTarget.value = ""
    this.filter()
    this.dialogTarget.showModal()
    this.inputTarget.focus()
  }

  close() {
    this.cancelSearch()
    this.dialogTarget.close()
  }

  filter() {
    const query = this.inputTarget.value.trim()
    if (query !== this.remoteQuery) {
      this.remote = []
      this.remoteQuery = null
    }
    this.matches = this.build(query)
    this.selected = 0
    this.render()
    this.searchServer(query)
  }

  build(query) {
    const words = normalize(query).split(/\s+/).filter(Boolean)
    const matches = (item) => words.every((word) => normalize(`${item.label} ${item.hint || ""} ${item.group} ${item.keywords || ""}`).includes(word))
    const local = words.length ? [...this.items, ...this.serverEntries()].filter(matches) : this.items
    const recentUrls = this.recentUrls()
    const pool = words.length ? local : [...this.items, ...this.serverEntries()]
    const recent = recentUrls.map((url) => pool.find((item) => item.url === url && !item.method)).filter(Boolean)
      .map((item) => ({ ...item, group: t("command_palette.recent") }))
    const rest = byGroup(local.filter((item) => !recent.some((entry) => entry.url === item.url && !item.method)))
    return [...recent, ...rest, ...this.remote, ...this.searches(query)]
  }

  // "Web › Packages"… and, for an operator, "Inventory Web": built here (only
  // listed once something is typed) rather than sent for each server in
  // every page.
  serverEntries() {
    if (!this.serverItems) {
      const { serverTabs, serverActions } = this.dialogTarget.dataset
      const tabs = Object.entries(JSON.parse(serverTabs || "{}"))
      const servers = this.items.filter((item) => item.server)
      const actions = serverActions ? servers.map((server) => ({ group: t("command_palette.actions"), label: t("command_palette.inventory", { server: server.label }),
        hint: server.hint, keywords: server.keywords, url: `${server.url}/inventory`, method: "post" })) : []
      this.serverItems = [...actions, ...servers.flatMap((server) =>
        tabs.map(([tab, label]) => ({ group: t("command_palette.server_tabs"), label: `${server.label} › ${label}`, url: `${server.url}?tab=${tab}` })))]
    }
    return this.serverItems
  }

  // "Find the package “…”", "Search “…” in the journal", for a port number
  // "Who exposes port …?", and for a host name "Who has the DNS name …?"
  // (when a DNS source is on).
  searches(query) {
    if (query.length < 2) return []
    const { packagesUrl, portsUrl, dnsUrl, journalUrl } = this.dialogTarget.dataset
    const searches = []
    if (/^\d{1,5}$/.test(query) && Number(query) <= 65535) {
      searches.push({ group: t("command_palette.search"), search: true, label: t("command_palette.port", { port: query }), url: `${portsUrl}?q=${query}` })
    }
    if (dnsUrl && /^[a-z0-9-]+(\.[a-z0-9-]+)+\.?$/i.test(query)) {
      searches.push({ group: t("command_palette.search"), search: true, label: t("command_palette.dns_name", { name: query }), url: `${dnsUrl}?q=${encodeURIComponent(query)}` })
    }
    searches.push({ group: t("command_palette.search"), search: true, label: t("command_palette.package", { package: query }), url: `${packagesUrl}?q=${encodeURIComponent(query)}` })
    searches.push({ group: t("command_palette.search"), search: true, label: t("command_palette.journal", { text: query }), url: `${journalUrl}?q=${encodeURIComponent(query)}` })
    return searches
  }

  // The CVEs, packages and notes matching the text, asked once the typing
  // pauses; an older request still running is cancelled.
  searchServer(query) {
    this.cancelSearch()
    const { searchUrl } = this.dialogTarget.dataset
    if (!searchUrl || query.length < 2 || query === this.remoteQuery) return

    this.searchTimer = setTimeout(async () => {
      this.searchRequest = new AbortController()
      try {
        const response = await fetch(`${searchUrl}?q=${encodeURIComponent(query)}`, { headers: { Accept: "application/json" }, signal: this.searchRequest.signal })
        if (!response.ok || this.inputTarget.value.trim() !== query) return
        const { results } = await response.json()
        this.remote = results
        this.remoteQuery = query
        // The entry chosen stays chosen, but a "search …" fallback gives way to the first result.
        const selected = this.matches[this.selected]
        this.matches = this.build(query)
        const kept = selected?.search ? -1 : this.matches.findIndex((item) => item.url === selected?.url && item.label === selected?.label)
        this.selected = Math.max(kept, 0)
        this.render()
      } catch (error) {
        if (error.name !== "AbortError") throw error
      }
    }, SEARCH_DELAY)
  }

  cancelSearch() {
    clearTimeout(this.searchTimer)
    this.searchRequest?.abort()
  }

  navigate(event) {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault()
      const step = event.key === "ArrowDown" ? 1 : -1
      this.selected = (this.selected + step + this.matches.length) % Math.max(this.matches.length, 1)
      this.render()
    } else if (event.key === "Enter") {
      event.preventDefault()
      this.visit(this.matches[this.selected])
    }
  }


  visit(item) {
    if (!item) return
    this.close()
    if (item.method === "post") return this.submit(item.url)
    if (!item.search) this.remember(item.url)
    window.Turbo.visit(item.url)
  }

  // An action: a form with the CSRF token, sent through Turbo.
  submit(url) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = url
    form.hidden = true
    const param = document.querySelector("meta[name=csrf-param]")?.content
    const token = document.querySelector("meta[name=csrf-token]")?.content
    if (param && token) {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = param
      input.value = token
      form.append(input)
    }
    document.body.append(form)
    form.requestSubmit()
  }

  // The entries opened lately, most recent first, kept in this browser only
  // (none in a private window or without storage).
  recentUrls() {
    try {
      const urls = JSON.parse(localStorage.getItem(RECENT_KEY) || "[]")
      return Array.isArray(urls) ? urls.filter((url) => typeof url === "string") : []
    } catch {
      return []
    }
  }

  remember(url) {
    try {
      localStorage.setItem(RECENT_KEY, JSON.stringify([url, ...this.recentUrls().filter((other) => other !== url)].slice(0, RECENT_MAX)))
    } catch {
      // No storage: nothing remembered.
    }
  }

  render() {
    this.resultsTarget.replaceChildren()
    this.emptyTarget.hidden = this.matches.some((item) => !item.search)
    let group = null

    this.matches.forEach((item, index) => {
      if (item.group !== group) {
        group = item.group
        const heading = document.createElement("li")
        heading.setAttribute("role", "presentation")
        heading.className = "px-2 pb-1 pt-3 text-xs font-semibold uppercase tracking-wide text-ink-3"
        heading.textContent = group
        this.resultsTarget.append(heading)
      }

      const option = document.createElement("li")
      option.id = `command-palette-option-${index}`
      option.setAttribute("role", "option")
      option.setAttribute("aria-selected", index === this.selected)
      option.className = "command-palette-item flex cursor-pointer items-center justify-between gap-3 rounded-md px-3 py-2 text-sm aria-selected:bg-accent-fill aria-selected:text-white"
      const label = document.createElement("span")
      label.className = "truncate font-medium"
      label.textContent = item.label
      option.append(label)
      if (item.hint) {
        const hint = document.createElement("span")
        hint.className = "truncate font-mono text-xs opacity-70"
        hint.textContent = item.hint
        option.append(hint)
      }
      option.addEventListener("mousemove", () => { if (this.selected !== index) { this.selected = index; this.render() } })
      option.addEventListener("click", () => this.visit(item))
      this.resultsTarget.append(option)
      if (index === this.selected) option.scrollIntoView({ block: "nearest" })
    })
    if (this.matches.length) {
      this.inputTarget.setAttribute("aria-activedescendant", `command-palette-option-${this.selected}`)
    } else {
      this.inputTarget.removeAttribute("aria-activedescendant")
    }
  }
}

function normalize(text) {
  return text.normalize("NFD").replace(/\p{Diacritic}/gu, "").toLowerCase()
}

// The entries of a group together, the groups in the order they first appear
// (the fleet action and the servers' ones under one heading).
function byGroup(items) {
  const groups = new Map()
  items.forEach((item) => groups.set(item.group, [...(groups.get(item.group) || []), item]))
  return [...groups.values()].flat()
}
