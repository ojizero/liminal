export const platform = navigator.userAgentData?.platform || navigator.platform || ""
const isWindowsPlatform = /win/i.test(platform)

const usesModKey = (event) => {
  if (isWindowsPlatform) return event.ctrlKey
  return event.metaKey
}

const detectShortcutPlatform = () => {
  if (/mac/i.test(platform)) return "mac"
  if (/win/i.test(platform)) return "windows"
  return "linux"
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

const looksLikeUrl = (text) => {
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

const normalizePastedUrl = (text) => {
  const trimmed = text.trim()
  return /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`
}

const LinkShortcuts = {
  mounted() {
    this.pushEvent("set_shortcut_platform", {platform: detectShortcutPlatform()})

    this.onKeyDown = (event) => {
      if (event.repeat) return

      const key = event.key?.toLowerCase()
      if (key === "k" && usesModKey(event)) {
        event.preventDefault()
        this.pushEvent("shortcut_focus_new_link", {})
        return
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
    window.addEventListener("paste", this.onPaste, true)

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
    window.removeEventListener("paste", this.onPaste, true)
  }
}

export default LinkShortcuts
