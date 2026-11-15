import { Controller } from "@hotwired/stimulus"

// Saves a text of the page as a file (backup codes…), without asking the
// server again: data-download-content-value and data-download-filename-value.
export default class extends Controller {
  static values = { content: String, filename: String }

  save() {
    const url = URL.createObjectURL(new Blob([this.contentValue], { type: "text/plain;charset=utf-8" }))
    const link = document.createElement("a")
    link.href = url
    link.download = this.filenameValue
    document.body.append(link)
    link.click()
    link.remove()
    setTimeout(() => URL.revokeObjectURL(url), 1000)
  }
}
