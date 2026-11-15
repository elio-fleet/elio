import { Controller } from "@hotwired/stimulus"

// A link that takes the address bar's query when clicked (its path kept, the
// page number dropped): a search typed meanwhile reloaded only the results
// frame, so the link written with the page is behind (e.g. an export).
export default class extends Controller {
  follow() {
    const url = new URL(this.element.href)
    const query = new URLSearchParams(window.location.search)
    query.delete("page")
    url.search = query.toString()
    this.element.href = url.toString()
  }
}
