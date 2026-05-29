const CopyToClipboard = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.clipboardText
      navigator.clipboard.writeText(text)
    })
  }
}

export default CopyToClipboard
