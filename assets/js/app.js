// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/liminal"
import topbar from "../vendor/topbar"
import Masonry from "./masonry_hook"

const platform = navigator.userAgentData?.platform || navigator.platform || ""
const isWindowsPlatform = /win/i.test(platform)

const usesModKey = (event) => {
  if (isWindowsPlatform) return event.ctrlKey
  return event.metaKey
}

const detectShortcutPlatform = () => {
  const platform = navigator.userAgentData?.platform || navigator.platform || ""

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

    window.addEventListener("keydown", this.onKeyDown, true)

    this.handleEvent("focus-new-link-url", () => {
      const input = document.querySelector("#link_url")
      if (input) input.focus()
    })
  },

  destroyed() {
    window.removeEventListener("keydown", this.onKeyDown, true)
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, Masonry, LinkShortcuts},
  metadata: {
    keydown: (event) => ({
      key: event.key,
      metaKey: event.metaKey,
      ctrlKey: event.ctrlKey,
      shiftKey: event.shiftKey,
      altKey: event.altKey,
      repeat: event.repeat,
      code: event.code,
      platform,
      targetTagName: event.target?.tagName,
      targetType: event.target?.type,
      targetIsContentEditable: event.target?.isContentEditable
    })
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Close dropdowns when clicking outside
document.addEventListener("click", (event) => {
  document.querySelectorAll("details.dropdown[open]").forEach((details) => {
    if (!details.contains(event.target)) {
      details.removeAttribute("open")
    }
  })
})

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

