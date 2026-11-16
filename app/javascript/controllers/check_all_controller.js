import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Checks every checkbox target, or unchecks them all when they already are.
// toggleGroup does the same for the checkboxes whose data-groups (space
// separated ids) contain the clicked button's data-check-all-group-param.
// With a count target, says how many are checked (refresh on each change:
// data-action="change->check-all#refresh").
export default class extends Controller {
  static targets = ["checkbox", "count"]

  connect() {
    this.refresh()
  }

  toggle() {
    this.#toggle(this.checkboxTargets)
  }

  toggleGroup({ params: { group } }) {
    this.#toggle(this.checkboxTargets.filter((checkbox) => (checkbox.dataset.groups || "").split(" ").includes(String(group))))
  }

  refresh() {
    if (!this.hasCountTarget) return

    const count = this.checkboxTargets.filter((checkbox) => checkbox.checked).length
    this.countTarget.textContent = t("selection.count", { count })
  }

  #toggle(checkboxes) {
    const check = !checkboxes.every((checkbox) => checkbox.checked)
    checkboxes.forEach((checkbox) => (checkbox.checked = check))
    this.refresh()
  }
}
