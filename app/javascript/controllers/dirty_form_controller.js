import { Controller } from "@hotwired/stimulus"

// The one Save of a page: the save bar (target "bar") appears as soon as a
// field differs from its value at load, says how many changed, and the
// changed fields get the class "is-dirty". "Cancel" puts the values back.
export default class extends Controller {
  static targets = ["bar", "summary"]

  connect() {
    this.initial = new Map(this.fields.map((field) => [field, this.valueOf(field)]))
    this.update = this.update.bind(this)
    this.element.addEventListener("input", this.update)
    this.element.addEventListener("change", this.update)
    this.update()
  }

  disconnect() {
    this.element.removeEventListener("input", this.update)
    this.element.removeEventListener("change", this.update)
  }

  get fields() {
    return [...this.element.elements].filter((field) => field.name && !["hidden", "submit", "button"].includes(field.type) && field.name !== "authenticity_token")
  }

  valueOf(field) {
    if (field.type === "checkbox" || field.type === "radio") return field.checked
    if (field.multiple) return [...field.selectedOptions].map((option) => option.value).join("\n")
    return field.value
  }

  get changed() {
    return this.fields.filter((field) => this.initial.has(field) && this.initial.get(field) !== this.valueOf(field))
  }

  update() {
    const changed = this.changed
    this.fields.forEach((field) => field.classList.toggle("is-dirty", changed.includes(field)))
    if (!this.hasBarTarget) return
    this.barTarget.hidden = changed.length === 0
    if (this.hasSummaryTarget) {
      const template = changed.length === 1 ? this.summaryTarget.dataset.one : this.summaryTarget.dataset.other
      this.summaryTarget.textContent = (template || "").replace("%{count}", changed.length)
    }
  }

  reset() {
    this.initial.forEach((value, field) => {
      if (field.type === "checkbox" || field.type === "radio") field.checked = value
      else if (field.multiple) [...field.options].forEach((option) => (option.selected = value.split("\n").includes(option.value)))
      else field.value = value
    })
    this.update()
  }
}
