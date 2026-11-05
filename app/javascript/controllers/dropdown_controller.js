import { Controller } from "@hotwired/stimulus"

// A menu built on <details>: the <summary> is the button, the items are the
// [role=menuitem] elements of the panel. Closes on a click outside, on Escape
// (focus goes back to the button) and after an item is chosen; the arrow keys
// move between items.
export default class extends Controller {
  connect() {
    this.closeOnOutsideClick = (event) => {
      if (this.element.open && !this.element.contains(event.target)) this.close()
    }
    document.addEventListener("click", this.closeOnOutsideClick)
  }

  disconnect() {
    document.removeEventListener("click", this.closeOnOutsideClick)
  }

  get items() {
    return [...this.element.querySelectorAll("[role=menuitem]")].filter((item) => !item.disabled)
  }

  keydown(event) {
    const items = this.items
    const index = items.indexOf(document.activeElement)
    switch (event.key) {
      case "Escape":
        if (!this.element.open) return
        event.preventDefault()
        this.close()
        this.element.querySelector("summary").focus()
        break
      case "ArrowDown":
        event.preventDefault()
        this.element.open = true
        items[(index + 1) % items.length]?.focus()
        break
      case "ArrowUp":
        event.preventDefault()
        this.element.open = true
        items[(index - 1 + items.length) % items.length]?.focus()
        break
      case "Home":
      case "End":
        if (index < 0) return
        event.preventDefault()
        items[event.key === "Home" ? 0 : items.length - 1]?.focus()
        break
    }
  }

  // After a choice (link followed, form submitted): closed once the click
  // has done its work, so a button_to still submits its form.
  chosen(event) {
    if (event.target.closest("[role=menuitem]")) setTimeout(() => this.close())
  }

  close() {
    this.element.open = false
  }
}
