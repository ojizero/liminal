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
import CopyToClipboard from "./copy_to_clipboard_hook"
import LinkShortcuts, {platform} from "./link_shortcuts_hook"
import ConnectionStatus from "./connection_status_hook"
import {initConnectionResilience} from "./connection_resilience"

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: () => ({
    _csrf_token: document.querySelector("meta[name='csrf-token']").getAttribute("content")
  }),
  hooks: {...colocatedHooks, Masonry, LinkShortcuts, CopyToClipboard, ConnectionStatus},
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

// Show progress bar on live navigation and form submits (not connection recovery)
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", (event) => {
  const {kind, errorKind} = event.detail || {}
  if (kind === "error" && errorKind === "client") return
  topbar.show(300)
})
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// Close dropdowns when clicking outside, or on Escape as the modals do
const closeDropdowns = (shouldClose) => {
  document.querySelectorAll("details.dropdown[open]").forEach((details) => {
    if (shouldClose(details)) details.removeAttribute("open")
  })
}

document.addEventListener("click", (event) => {
  closeDropdowns((details) => !details.contains(event.target))
})

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeDropdowns(() => true)
})

// connect if there are any LiveViews on the page
liveSocket.connect()
initConnectionResilience(liveSocket)

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

