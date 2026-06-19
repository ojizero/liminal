const ConnectionStatus = {
  mounted() {
    this.onLost = () => this.showReconnecting()
    this.onRestored = () => this.showRestored()
    this.onStalled = () => this.showRetry()
    this.retry = (event) => {
      event?.stopPropagation()
      if (typeof window.lvReconnect === "function") window.lvReconnect()
      this.showReconnecting()
    }

    window.addEventListener("lv:connection-lost", this.onLost)
    window.addEventListener("lv:connection-restored", this.onRestored)
    window.addEventListener("lv:connection-stalled", this.onStalled)

    this.el.querySelector("#client-error-retry")?.addEventListener("click", this.retry)
    this.el.querySelector("#server-error-retry")?.addEventListener("click", this.retry)
  },

  destroyed() {
    window.removeEventListener("lv:connection-lost", this.onLost)
    window.removeEventListener("lv:connection-restored", this.onRestored)
    window.removeEventListener("lv:connection-stalled", this.onStalled)
    clearTimeout(this.restoredTimer)
  },

  showReconnecting() {
    for (const id of ["client-error-message", "server-error-message"]) {
      const el = this.el.querySelector(`#${id}`)
      if (!el) continue
      const message = el.querySelector('[data-role="message"]')
      const spinner = el.querySelector('[data-role="spinner"]')
      if (message) message.textContent = "Reconnecting…"
      spinner?.classList.remove("hidden")
    }
    this.hideRetry()
  },

  showRetry() {
    for (const id of ["client-error-message", "server-error-message"]) {
      const el = this.el.querySelector(`#${id}`)
      if (!el) continue
      const message = el.querySelector('[data-role="message"]')
      const spinner = el.querySelector('[data-role="spinner"]')
      if (message) message.textContent = "Still offline. Check your connection."
      spinner?.classList.add("hidden")
    }
    for (const id of ["client-error-retry", "server-error-retry"]) {
      const btn = this.el.querySelector(`#${id}`)
      if (btn) btn.classList.remove("hidden")
    }
  },

  hideRetry() {
    for (const id of ["client-error-retry", "server-error-retry"]) {
      const btn = this.el.querySelector(`#${id}`)
      if (btn) btn.classList.add("hidden")
    }
  },

  showRestored() {
    this.hideRetry()
    const toast = this.el.querySelector("#connection-restored")
    if (!toast) return

    toast.removeAttribute("hidden")
    toast.classList.remove("hidden")
    clearTimeout(this.restoredTimer)
    this.restoredTimer = setTimeout(() => {
      toast.setAttribute("hidden", "")
      toast.classList.add("hidden")
    }, 3000)
  }
}

export default ConnectionStatus
