const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.clipboardText
      navigator.clipboard.writeText(text).then(() => {
        this.pushEvent("copied_to_clipboard", {})
      })
    })
  }
}

export default CopyToClipboard
