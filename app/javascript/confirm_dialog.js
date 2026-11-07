import { t } from "i18n"

// Replaces the browser's confirm() for data-turbo-confirm with the app's
// <dialog id="confirm-dialog">. The accept button's label and colour come from
// data-confirm-label / data-confirm-variant ("danger") on the submitter or form.
export function confirmDialog(message, form, submitter) {
  const dialog = document.getElementById("confirm-dialog")
  if (!dialog) return Promise.resolve(window.confirm(message))

  const option = (name) => submitter?.dataset[name] || form?.dataset[name]
  const accept = dialog.querySelector("[data-confirm-accept]")
  dialog.querySelector("[data-confirm-message]").textContent = message
  accept.textContent = option("confirmLabel") || t("confirm.accept")
  accept.dataset.variant = option("confirmVariant") || "primary"

  const opening = ++openings
  dialog.returnValue = ""
  dialog.showModal()
  accept.focus()

  // The browser fires "close" after the dialog is closed, as a separate task:
  // when a confirmation is opened right after another one was answered, that
  // late event must not answer the new one. Each opening answers only once,
  // to the close of its own opening (a newer opening answers the older "no").
  return new Promise((resolve) => {
    const onClose = () => {
      if (opening === openings && dialog.open) return
      dialog.removeEventListener("close", onClose)
      resolve(opening === openings && dialog.returnValue === "confirm")
    }
    dialog.addEventListener("close", onClose)
  })
}

let openings = 0

// Clicking the backdrop (outside the panel) cancels.
document.addEventListener("click", (event) => {
  if (event.target.id === "confirm-dialog") event.target.close("cancel")
})
