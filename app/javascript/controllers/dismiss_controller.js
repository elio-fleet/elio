import { Controller } from "@hotwired/stimulus"

// A notice the reader can hide: removes the element and, with a `cookie`
// value, remembers it for a year in that browser (read by the server, which
// then stops rendering it).
export default class extends Controller {
  static values = { cookie: String }

  dismiss() {
    if (this.cookieValue) {
      const secure = location.protocol === "https:" ? "; Secure" : ""
      document.cookie = `${this.cookieValue}=1; Max-Age=31536000; Path=/; SameSite=Lax${secure}`
    }
    this.element.remove()
  }
}
