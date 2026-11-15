import { Controller } from "@hotwired/stimulus"
import { t } from "i18n"

// Says while typing how strong a new password is: below the minimum length,
// then weak (short, one kind of character, repeated or well-known), fair or
// strong. Only a hint: the server checks the minimum length alone.
//
//   <div data-controller="password-strength" data-password-strength-minimum-value="12">
//     <input data-password-strength-target="input" data-action="input->password-strength#update">
//     <div data-password-strength-target="meter" hidden><div data-password-strength-target="bar"></div></div>
//     <p data-password-strength-target="label" aria-live="polite"></p>
//   </div>
const LEVELS = {
  too_short: { width: "15%", tone: "bg-crit" },
  weak: { width: "33%", tone: "bg-crit" },
  fair: { width: "66%", tone: "bg-warn" },
  strong: { width: "100%", tone: "bg-good" }
}
const WELL_KNOWN = /pass(word)?|mot ?de ?passe|azerty|qwerty|123|admin|elio|letmein|welcome|bienvenue/i

export default class extends Controller {
  static targets = ["input", "meter", "bar", "label"]
  static values = { minimum: Number }

  connect() {
    this.update()
  }

  update() {
    const password = this.inputTarget.value
    this.meterTarget.hidden = password === ""
    this.element.dataset.level = ""
    if (password === "") {
      this.labelTarget.textContent = ""
      return
    }

    const level = this.level(password)
    this.element.dataset.level = level
    this.barTarget.style.width = LEVELS[level].width
    this.barTarget.className = `h-full rounded-full ${LEVELS[level].tone}`
    this.labelTarget.textContent = t(`password_strength.${level}`, { count: this.minimumValue })
  }

  level(password) {
    const length = [...password].length
    if (length < this.minimumValue) return "too_short"

    const kinds = [/[a-z]/, /[A-Z]/, /\d/, /[^A-Za-z0-9]/].filter((kind) => kind.test(password)).length
    const distinct = new Set(password.toLowerCase()).size
    if (kinds < 2 || distinct < length / 2 || /(.)\1\1/.test(password) || WELL_KNOWN.test(password)) return "weak"

    const score = (length >= this.minimumValue + 4 ? 1 : 0) + (length >= 20 ? 1 : 0) + (kinds >= 3 ? 1 : 0)
    return score >= 2 ? "strong" : "fair"
  }
}
