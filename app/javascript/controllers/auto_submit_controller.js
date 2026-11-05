import { Controller } from "@hotwired/stimulus"

// Submits its form as soon as a field changes (filters), or shortly after
// the user stops typing (submitLater, for search fields).
//
// When the form reloads a results frame (data-turbo-frame), the address bar
// follows the results once they are shown. Not through Turbo's
// data-turbo-action: that promotes the frame load to a visit, which
// cancelled a link clicked while the search was still loading.
export default class extends Controller {
  connect() {
    this.frame = this.element.dataset.turboFrame && document.getElementById(this.element.dataset.turboFrame)
    if (!this.frame) return

    this.leaving = false
    this.onVisit = () => (this.leaving = true)
    this.onFrameLoad = () => {
      if (!this.leaving && this.frame.src) history.replaceState(history.state, "", this.frame.src)
    }
    document.addEventListener("turbo:visit", this.onVisit)
    this.frame.addEventListener("turbo:frame-load", this.onFrameLoad)
  }

  submit() {
    clearTimeout(this.timeout)
    this.element.requestSubmit()
  }

  submitLater() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), 300)
  }

  disconnect() {
    clearTimeout(this.timeout)
    document.removeEventListener("turbo:visit", this.onVisit)
    this.frame?.removeEventListener("turbo:frame-load", this.onFrameLoad)
  }
}
