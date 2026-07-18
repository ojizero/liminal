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

  // LiveView sets `unloaded = true` on every `pagehide`, then calls
  // `location.reload()` from socket `onOpen` while that flag is set.
  //
  // Tab suspension race (the "odd restore"):
  //   1. pagehide → unloaded=true, websocket drops
  //   2. socket reconnects while the tab is still hidden
  //   3. onOpen sees unloaded → full reload in the background
  //   4. user returns to a mid-reload / dead-rendered page
  //
  // For ordinary hides (tab switch, minimize, mobile freeze without bfcache),
  // clear the flag immediately so a background reconnect can rejoin in place.
  // Keep it for bfcache entries (`persisted`) so LiveView's pageshow handler
  // can intentionally reload the stale snapshot.
  window.addEventListener("pagehide", (event) => {
    captureScroll()
    if (!event.persisted) {
      liveSocket.unloaded = false
    }
  })

  // Belt-and-suspenders for browsers that resume without a clean pagehide path.
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      liveSocket.unloaded = false
    } else {
      captureScroll()
    }
  })

  document.addEventListener("resume", () => {
    liveSocket.unloaded = false
  })

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
