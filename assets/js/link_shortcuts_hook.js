export const platform = navigator.userAgentData?.platform || navigator.platform || ""
const isWindowsPlatform = /win/i.test(platform)

// iOS Safari (and all iOS browsers) cannot probe the clipboard in the background.
export const isIOS = () => {
  if (/iPad|iPhone|iPod/i.test(navigator.userAgent)) return true

  return navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1
}

const usesModKey = (event) => {
  if (isWindowsPlatform) return event.ctrlKey
  return event.metaKey
}

const usesNoteSubmitModKey = (event) => {
  if (/mac/i.test(platform)) return event.metaKey
  return event.ctrlKey
}

const detectShortcutPlatform = () => {
  if (/mac/i.test(platform)) return "mac"
  if (/win/i.test(platform)) return "windows"
  return "linux"
}

// Touch-first phones/tablets rarely expose keyboard shortcuts; hide shortcut hints.
export const hasLikelyHardwareKeyboard = () => {
  if (window.matchMedia("(hover: hover) and (pointer: fine)").matches) {
    return true
  }

  if (navigator.maxTouchPoints === 0) {
    return true
  }

  return false
}

const parseDigitShortcut = (event) => {
  const codeMatch = /^(?:Digit|Numpad)([1-9])$/.exec(event.code || "")
  if (codeMatch) return Number.parseInt(codeMatch[1], 10)

  const key = event.key || ""
  const keyDigit = Number.parseInt(key, 10)
  if (!Number.isNaN(keyDigit) && keyDigit >= 1 && keyDigit <= 9) return keyDigit

  const keyCode = Number.parseInt(`${event.keyCode ?? ""}`, 10)
  if (!Number.isNaN(keyCode) && keyCode >= 49 && keyCode <= 57) return keyCode - 48

  return null
}

const isEditableTarget = (target) => {
  if (!target?.closest) return false

  return !!target.closest("input, textarea, select, [contenteditable=true]")
}

export const looksLikeUrl = (text) => {
  const trimmed = text.trim()
  if (!trimmed || /\s/.test(trimmed)) return false

  try {
    const withScheme = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`
    const url = new URL(withScheme)
    return url.hostname.includes(".")
  } catch {
    return false
  }
}

export const normalizePastedUrl = (text) => {
  const trimmed = text.trim()
  return /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`
}

const LinkShortcuts = {
  mounted() {
    const showKeyboardShortcutHints = hasLikelyHardwareKeyboard()

    this.pushEvent("set_shortcut_platform", {
      platform: detectShortcutPlatform(),
      show_keyboard_shortcut_hints: showKeyboardShortcutHints,
      show_clipboard_paste_button: showKeyboardShortcutHints || !isIOS()
    })

    this.onKeyDown = (event) => {
      if (event.repeat) return

      const key = event.key?.toLowerCase()
      if (key === "enter" && usesNoteSubmitModKey(event) && !event.shiftKey && !event.altKey) {
        if (event.target?.id === "link_note") {
          event.preventDefault()
          document.querySelector("#link-form")?.requestSubmit()
          return
        }
      }

      if (!isEditableTarget(event.target)) {
        if (key === "r" && !usesModKey(event) && !event.shiftKey && !event.altKey) {
          event.preventDefault()
          document.querySelector("#random-link")?.click()
          return
        }

        if (key === "f" && !usesModKey(event) && !event.shiftKey && !event.altKey) {
          event.preventDefault()
          const searchInput = document.querySelector("#link-search-input")
          if (searchInput) {
            searchInput.focus()
            searchInput.select?.()
          }
          return
        }

        if (key === "j" && !usesModKey(event) && !event.shiftKey && !event.altKey) {
          event.preventDefault()
          this.pushEvent("shortcut_focus_new_link", {})
          return
        }
      }

      const digit = parseDigitShortcut(event)
      if (digit && event.shiftKey && usesModKey(event) && !event.altKey) {
        event.preventDefault()
        this.pushEvent("shortcut_toggle_tag_by_index", {index: digit})
      }
    }

    this.onPaste = (event) => {
      if (isEditableTarget(event.target)) return

      event.preventDefault()

      const text = event.clipboardData?.getData("text") ?? ""

      if (looksLikeUrl(text)) {
        this.pushEvent("shortcut_paste_link", {url: normalizePastedUrl(text)})
      } else {
        this.pushEvent("shortcut_paste_no_link", {})
      }
    }

    window.addEventListener("keydown", this.onKeyDown, true)

    // Touch-first browsers (notably iOS Chrome) show a persistent Paste affordance when
    // a global paste listener is registered. Desktop keeps paste-from-anywhere via Cmd/Ctrl+V.
    if (showKeyboardShortcutHints) {
      this.globalPasteEnabled = true
      window.addEventListener("paste", this.onPaste, true)
    }

    if (!showKeyboardShortcutHints && !isIOS()) {
      this.lastClipboardHasLink = null

      this.refreshClipboardLinkState = async () => {
        if (!navigator.clipboard?.readText) return

        try {
          const text = await navigator.clipboard.readText()
          const hasLink = looksLikeUrl(text)

          if (hasLink !== this.lastClipboardHasLink) {
            this.lastClipboardHasLink = hasLink
            this.pushEvent("set_clipboard_has_link", {has_link: hasLink})
          }
        } catch {
          // Clipboard may be unreadable until the user interacts with the page.
        }
      }

      this.pasteFromClipboard = async () => {
        if (!navigator.clipboard?.readText) {
          this.pushEvent("shortcut_paste_no_link", {})
          return
        }

        try {
          const text = await navigator.clipboard.readText()

          if (looksLikeUrl(text)) {
            this.pushEvent("shortcut_paste_link", {url: normalizePastedUrl(text)})
          } else {
            this.pushEvent("shortcut_paste_no_link", {})
          }
        } catch {
          this.pushEvent("shortcut_paste_no_link", {})
        }
      }

      this.onVisibilityChange = () => {
        if (document.visibilityState === "visible") {
          this.refreshClipboardLinkState()
        }
      }

      this.onPasteButtonClick = (event) => {
        const button = event.target.closest("#link-url-paste-from-clipboard")
        if (!button || button.disabled) return

        event.preventDefault()
        this.pasteFromClipboard()
      }

      document.addEventListener("visibilitychange", this.onVisibilityChange)
      window.addEventListener("focus", this.refreshClipboardLinkState)
      window.addEventListener("pageshow", this.refreshClipboardLinkState)
      document.addEventListener("click", this.onPasteButtonClick, true)

      this.clipboardPollInterval = window.setInterval(() => {
        if (document.visibilityState === "visible") {
          this.refreshClipboardLinkState()
        }
      }, 1500)

      this.refreshClipboardLinkState()
    }

    this.handleEvent("focus-new-link-url", ({scroll} = {}) => {
      const card = document.querySelector("#new-link-card")
      if (scroll && card) {
        card.scrollIntoView({behavior: "smooth", block: "nearest"})
      }

      const input = document.querySelector("#link_url")
      if (input) {
        input.focus()
        input.setSelectionRange(input.value.length, input.value.length)
      }
    })
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeyDown, true)

    if (this.globalPasteEnabled) {
      window.removeEventListener("paste", this.onPaste, true)
    }

    if (this.refreshClipboardLinkState) {
      document.removeEventListener("visibilitychange", this.onVisibilityChange)
      window.removeEventListener("focus", this.refreshClipboardLinkState)
      window.removeEventListener("pageshow", this.refreshClipboardLinkState)
      document.removeEventListener("click", this.onPasteButtonClick, true)
      window.clearInterval(this.clipboardPollInterval)
    }
  }
}

export default LinkShortcuts
