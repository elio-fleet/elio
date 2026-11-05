import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Quick search over pages, groups, servers (also by host name and IP, the
// `keywords`), keyring keys and the tabs of the servers (built here, listed
// once something is typed), plus a fleet
// package search and, for a number, the servers exposing that port.
// Opens with ⌘K / Ctrl+K or the sidebar button; arrows to move, Enter to
// open, Escape to close.
export default class extends Controller {
  static targets = ["dialog", "input", "results", "empty", "items"]

  connect() {
    this.items = JSON.parse(this.itemsTarget.textContent)
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
  }

  open() {
    this.inputTarget.value = ""
    this.filter()
    this.dialogTarget.showModal()
    this.inputTarget.focus()
  }

  close() {
    this.dialogTarget.close()
  }

  filter() {
    const query = this.inputTarget.value.trim()
    const words = normalize(query).split(/\s+/).filter(Boolean)
    const matches = (item) => words.every((word) => normalize(`${item.label} ${item.hint || ""} ${item.group} ${item.keywords || ""}`).includes(word))
    this.matches = this.items.filter(matches)
    if (words.length) this.matches.push(...this.serverTabs().filter(matches))
    this.matches.push(...this.searches(query))
    this.selected = 0
    this.render()
  }

  // "Web › Packages"…: the tabs of every server, built here (only listed once
  // something is typed) rather than sent for each server in every page.
  serverTabs() {
    if (!this.tabItems) {
      const tabs = Object.entries(JSON.parse(this.dialogTarget.dataset.serverTabs || "{}"))
      this.tabItems = this.items.filter((item) => item.server).flatMap((server) =>
        tabs.map(([tab, label]) => ({ group: t("command_palette.server_tabs"), label: `${server.label} › ${label}`, url: `${server.url}?tab=${tab}` })))
    }
    return this.tabItems
  }

  // "Find the package “…”", for a port number "Who exposes port …?", and for
  // a host name "Who has the DNS name …?" (when a DNS source is on).
  searches(query) {
    if (query.length < 2) return []
    const { packagesUrl, portsUrl, dnsUrl } = this.dialogTarget.dataset
    const searches = []
    if (/^\d{1,5}$/.test(query) && Number(query) <= 65535) {
      searches.push({ group: t("command_palette.search"), search: true, label: t("command_palette.port", { port: query }), url: `${portsUrl}?q=${query}` })
    }
    if (dnsUrl && /^[a-z0-9-]+(\.[a-z0-9-]+)+\.?$/i.test(query)) {
      searches.push({ group: t("command_palette.search"), search: true, label: t("command_palette.dns_name", { name: query }), url: `${dnsUrl}?q=${encodeURIComponent(query)}` })
    }
    searches.push({ group: t("command_palette.search"), search: true, label: t("command_palette.package", { package: query }), url: `${packagesUrl}?q=${encodeURIComponent(query)}` })
    return searches
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
    window.Turbo.visit(item.url)
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
