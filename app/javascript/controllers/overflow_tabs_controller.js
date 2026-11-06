import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Tabs that do not fit the bar move into its "More" menu, from the last one,
// never the current tab. Recomputed when the bar is resized. Also drives the
// drop-down list shown instead on small screens.
export default class extends Controller {
  static targets = ["bar", "tab", "more", "item"]

  connect() {
    this.barTarget.classList.remove("overflow-x-auto")
    this.barTarget.classList.add("overflow-visible")
    this.observer = new ResizeObserver(() => this.layout())
    this.observer.observe(this.barTarget)
    this.layout()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  layout() {
    const bar = this.barTarget
    if (!bar.clientWidth) return
    this.tabTargets.forEach((tab) => (tab.hidden = false))
    this.itemTargets.forEach((item) => (item.hidden = true))
    this.moreTarget.hidden = true
    if (!this.overflowing) return

    this.moreTarget.hidden = false
    const movable = this.tabTargets.filter((tab) => !tab.hasAttribute("aria-current")).reverse()
    for (const tab of movable) {
      if (!this.overflowing) break
      tab.hidden = true
      this.itemTargets.find((item) => item.dataset.tab === tab.dataset.tab).hidden = false
    }
  }

  get overflowing() {
    const bar = this.barTarget
    const right = bar.getBoundingClientRect().right
    const visible = [...bar.children].filter((child) => !child.hidden)
    return visible.some((child) => child.getBoundingClientRect().right > right + 1)
  }

  visit(event) {
    Turbo.visit(event.target.value)
  }
}
