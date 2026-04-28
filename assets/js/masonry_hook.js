const Masonry = {
  mounted() {
    this._layout()

    this._resizeObserver = new ResizeObserver(() => this._layout())
    this._resizeObserver.observe(this.el)

    this._mutationObserver = new MutationObserver(() => this._layout())
    this._mutationObserver.observe(this.el, { childList: true, subtree: true })
  },

  updated() {
    this._layout()
  },

  destroyed() {
    this._resizeObserver?.disconnect()
    this._mutationObserver?.disconnect()
  },

  _layout() {
    cancelAnimationFrame(this._raf)
    this._raf = requestAnimationFrame(() => this._doLayout())
  },

  _doLayout() {
    const gap = 16
    const containerWidth = this.el.clientWidth
    if (containerWidth === 0) return

    let cols = 1
    if (containerWidth >= 1024) cols = 3
    else if (containerWidth >= 640) cols = 2

    const colWidth = (containerWidth - gap * (cols - 1)) / cols
    const colHeights = new Array(cols).fill(0)

    const items = this.el.querySelectorAll("[data-masonry-item]")

    items.forEach(item => {
      item.style.position = "absolute"
      item.style.width = `${colWidth}px`
    })

    // force reflow so heights are accurate at the new width
    void this.el.offsetHeight

    items.forEach(item => {
      if (item.offsetHeight === 0) return

      const shortest = Math.min(...colHeights)
      const col = colHeights.indexOf(shortest)

      item.style.left = `${col * (colWidth + gap)}px`
      item.style.top = `${colHeights[col]}px`

      colHeights[col] += item.offsetHeight + gap
    })

    const maxHeight = Math.max(...colHeights)
    this.el.style.height = `${maxHeight > 0 ? maxHeight - gap : 0}px`
  }
}

export default Masonry
