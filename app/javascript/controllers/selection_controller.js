import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Rows ticked in a list: shows the bar of actions (and how many rows are
// ticked) only while at least one is; the header checkbox ticks or unticks
// every row, and is half ticked when some are.
export default class extends Controller {
  static targets = ["checkbox", "all", "bar", "count"]

  connect() {
    this.update()
  }

  toggleAll() {
    this.checkboxTargets.forEach((checkbox) => (checkbox.checked = this.allTarget.checked))
    this.update()
  }

  clear() {
    this.checkboxTargets.forEach((checkbox) => (checkbox.checked = false))
    this.update()
  }

  update() {
    const total = this.checkboxTargets.length
    const count = this.checkboxTargets.filter((checkbox) => checkbox.checked).length
    this.barTarget.classList.toggle("hidden", count === 0)
    this.countTarget.textContent = t("selection.count", { count })
    if (this.hasAllTarget) {
      this.allTarget.checked = total > 0 && count === total
      this.allTarget.indeterminate = count > 0 && count < total
    }
  }
}
