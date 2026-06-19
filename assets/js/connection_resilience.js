const SCROLL_KEY = "lv:scroll-position"
const STALLED_MS = 15_000

/**
 * Graceful LiveView connection recovery for slow networks and mobile tab lifecycle.
 *
 * - Preserves scroll position across disconnects and forced reloads
 * - Prevents unnecessary full-page reload when returning from a backgrounded tab
 * - Surfaces connection state via custom events for the UI layer
 */
export function initConnectionResilience(liveSocket) {
  let wasDisconnected = false
  let stalledTimer = null
  let scrollObserver = null

  function captureScroll() {
    try {
      sessionStorage.setItem(
        SCROLL_KEY,
        JSON.stringify({
          x: window.scrollX,
          y: window.scrollY,
          path: window.location.pathname + window.location.search,
        }),
      )
    } catch (_error) {
      // sessionStorage may be unavailable in private browsing edge cases
    }
  }

  function restoreScroll() {
    let data

    try {
      const raw = sessionStorage.getItem(SCROLL_KEY)
      data = raw ? JSON.parse(raw) : null
    } catch (_error) {
      data = null
    }

    if (!data) return

    const currentPath = window.location.pathname + window.location.search
    if (data.path !== currentPath) return

    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        window.scrollTo(data.x, data.y)
        sessionStorage.removeItem(SCROLL_KEY)
      })
    })
  }

  function dispatch(name, detail = {}) {
    window.dispatchEvent(new CustomEvent(name, {detail}))
  }

  function clearStalledTimer() {
    if (stalledTimer) {
      clearTimeout(stalledTimer)
      stalledTimer = null
    }
  }

  function startStalledTimer() {
    clearStalledTimer()
    stalledTimer = setTimeout(() => dispatch("lv:connection-stalled"), STALLED_MS)
  }

  function markDisconnected() {
    if (!wasDisconnected) {
      wasDisconnected = true
      captureScroll()
      dispatch("lv:connection-lost")
      startStalledTimer()
    }
  }

  function markReconnected() {
    if (wasDisconnected) {
      wasDisconnected = false
      clearStalledTimer()
      restoreScroll()
      dispatch("lv:connection-restored")
    }
  }

  // Phoenix marks the socket as unloaded on pagehide, then reloads on the next
  // socket open — even when the page is still alive in a backgrounded tab.
  // Clearing the flag on visibility restore lets LiveView rejoin in place.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      liveSocket.unloaded = false
    } else {
      captureScroll()
    }
  })

  window.addEventListener("pagehide", captureScroll)

  if (sessionStorage.getItem(SCROLL_KEY)) {
    window.addEventListener("phx:page-loading-stop", restoreScroll, {once: true})
  }

  const socket = liveSocket.getSocket()

  socket.onClose(() => markDisconnected())

  window.addEventListener("phx:page-loading-start", (event) => {
    const {kind, errorKind} = event.detail || {}
    if (kind === "error" && errorKind === "client") {
      markDisconnected()
    }
  })

  function observeMainView() {
    const main = document.querySelector("[data-phx-main]")
    if (!main) return

    scrollObserver?.disconnect()

    scrollObserver = new MutationObserver(() => {
      const hasClientError = main.classList.contains("phx-client-error")
      const hasServerError = main.classList.contains("phx-server-error")
      const isConnected = main.classList.contains("phx-connected")

      if (hasClientError || hasServerError) {
        markDisconnected()
      } else if (isConnected) {
        markReconnected()
      }
    })

    scrollObserver.observe(main, {attributes: true, attributeFilter: ["class"]})

    if (main.classList.contains("phx-connected")) {
      wasDisconnected = false
    }
  }

  observeMainView()
  document.addEventListener("phx:update", observeMainView)

  window.lvReconnect = () => {
    captureScroll()
    liveSocket.unloaded = false
    clearStalledTimer()

    const currentSocket = liveSocket.getSocket()
    if (currentSocket.isConnected()) return

    currentSocket.connect()
  }

  return {captureScroll, restoreScroll}
}
