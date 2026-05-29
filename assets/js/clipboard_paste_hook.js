// Detects a URL on the user's clipboard and offers a one-click paste into the
// new-link URL field. Reading the system clipboard is only possible through the
// browser Clipboard API, which LiveView/HEEx and Phoenix.LiveView.JS cannot do,
// so a small JS hook is required.
//
// The feature is strictly opt-in and side-effect free:
//   * If the Clipboard read API is unavailable (e.g. Firefox web content,
//     insecure context) nothing is rendered and nothing happens.
//   * Auto-detection only reads the clipboard when permission is *already*
//     granted, so the user is never prompted unexpectedly or nagged.
//   * A neutral "Paste link from clipboard" button lets the user paste on
//     demand (an explicit user gesture), which is the only time a permission
//     prompt may appear.

const URL_RE = /^https?:\/\/\S+$/i
const MAX_LABEL_LEN = 48

const looksLikeUrl = (text) =>
  typeof text === "string" && URL_RE.test(text.trim())

const clipboardReadable = () =>
  window.isSecureContext !== false &&
  !!navigator.clipboard &&
  typeof navigator.clipboard.readText === "function"

const truncate = (text) =>
  text.length > MAX_LABEL_LEN ? `${text.slice(0, MAX_LABEL_LEN - 1)}…` : text

const ClipboardPaste = {
  mounted() {
    this.input = this.el
    this.control = document.getElementById("link-url-clipboard")
    this.action = document.getElementById("link-url-clipboard-action")
    this.label = document.getElementById("link-url-clipboard-label")
    this.dismissBtn = document.getElementById("link-url-clipboard-dismiss")

    // Bail out entirely if the affordance markup or the Clipboard API is
    // missing — no UI, no listeners, no side effects.
    if (!this.control || !this.action || !this.label || !this.dismissBtn) return
    if (!clipboardReadable()) return

    this.suggested = null
    this.dismissedValue = null

    this.onAction = (event) => {
      event.preventDefault()
      if (this.suggested) {
        this.fill(this.suggested)
      } else {
        this.readAndFill()
      }
    }
    this.action.addEventListener("click", this.onAction)

    this.onDismiss = (event) => {
      event.preventDefault()
      if (this.suggested) this.dismissedValue = this.suggested
      this.showNeutral()
    }
    this.dismissBtn.addEventListener("click", this.onDismiss)

    this.onInput = () => {
      if (this.input.value.trim() === "") {
        this.showNeutral()
        this.reveal()
      } else {
        this.hide()
      }
    }
    this.input.addEventListener("input", this.onInput)

    this.showNeutral()
    this.reveal()
    this.maybeAutoDetect()
  },

  // Only read the clipboard automatically when permission is already granted,
  // so the user is never prompted just by loading the page.
  maybeAutoDetect() {
    if (this.input.value.trim() !== "") return
    if (!navigator.permissions || typeof navigator.permissions.query !== "function") return

    navigator.permissions
      .query({name: "clipboard-read"})
      .then((status) => {
        if (status.state === "granted") this.peekClipboard()
        status.onchange = () => {
          if (status.state === "granted" && this.input.value.trim() === "") {
            this.peekClipboard()
          }
        }
      })
      .catch(() => {})
  },

  peekClipboard() {
    navigator.clipboard
      .readText()
      .then((text) => {
        const value = (text || "").trim()
        if (this.input.value.trim() !== "") return
        if (looksLikeUrl(value) && value !== this.dismissedValue) {
          this.showSuggestion(value)
        }
      })
      .catch(() => {})
  },

  readAndFill() {
    navigator.clipboard
      .readText()
      .then((text) => {
        const value = (text || "").trim()
        if (looksLikeUrl(value)) {
          this.fill(value)
        } else {
          this.flashLabel("No link found in clipboard")
        }
      })
      .catch(() => this.flashLabel("Clipboard access blocked"))
  },

  fill(url) {
    this.input.value = url
    this.input.dispatchEvent(new Event("input", {bubbles: true}))
    this.input.focus()
    this.hide()
  },

  showNeutral() {
    this.suggested = null
    this.label.textContent = "Paste link from clipboard"
    this.label.classList.remove("text-primary", "font-medium")
    this.dismissBtn.classList.add("hidden")
  },

  showSuggestion(url) {
    this.suggested = url
    this.label.textContent = `Paste ${truncate(url)}`
    this.label.classList.add("text-primary", "font-medium")
    this.dismissBtn.classList.remove("hidden")
    this.reveal()
  },

  reveal() {
    this.control.classList.remove("hidden")
    this.control.classList.add("flex")
  },

  hide() {
    this.control.classList.remove("flex")
    this.control.classList.add("hidden")
  },

  flashLabel(message) {
    const original = this.suggested
      ? `Paste ${truncate(this.suggested)}`
      : "Paste link from clipboard"
    this.label.textContent = message
    clearTimeout(this._flashTimer)
    this._flashTimer = setTimeout(() => {
      this.label.textContent = original
    }, 2000)
  },

  destroyed() {
    this.action?.removeEventListener("click", this.onAction)
    this.dismissBtn?.removeEventListener("click", this.onDismiss)
    this.input?.removeEventListener("input", this.onInput)
    clearTimeout(this._flashTimer)
  }
}

export default ClipboardPaste
