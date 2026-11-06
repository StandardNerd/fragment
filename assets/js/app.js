// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/fragment"
import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks},
})

topbar.config({barColors: {0: "#6366f1"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket

// Progressive enhancements for Fragment editor & copy buttons
const formatBytes = (bytes) => {
  if (bytes < 1024) return `${bytes} B`
  return `${(bytes / 1024).toFixed(1)} KB`
}

const initEditorEnhancements = () => {
  const textarea = document.querySelector("textarea.code-input")
  const statsEl = document.getElementById("paste-stats")
  const lineNumbersEl = document.getElementById("code-line-numbers")

  if (!textarea || textarea.dataset.editorEnhanced === "true") return
  textarea.dataset.editorEnhanced = "true"

  let renderedLineCount = lineNumbersEl ? lineNumbersEl.children.length : 0
  let currentActiveLine = 1

  const getActiveLine = () => {
    const pos = textarea.selectionStart ?? 0
    const val = textarea.value || ""
    let line = 1
    for (let i = 0; i < pos && i < val.length; i++) {
      if (val.charCodeAt(i) === 10) line++
    }
    return line
  }

  const syncActiveLine = () => {
    if (!lineNumbersEl) return
    const nextActive = getActiveLine()
    const prevEl = lineNumbersEl.children[currentActiveLine - 1]
    if (prevEl && currentActiveLine !== nextActive) {
      prevEl.classList.remove("active")
    }
    const nextEl = lineNumbersEl.children[nextActive - 1]
    if (nextEl && !nextEl.classList.contains("active")) {
      nextEl.classList.add("active")
    }
    currentActiveLine = nextActive
  }

  const updateLineNumbers = () => {
    if (!lineNumbersEl) return
    const val = textarea.value || ""
    const lineCount = Math.max(1, val.split(/\r?\n/).length)

    if (lineCount !== renderedLineCount) {
      const fragment = document.createDocumentFragment()
      const activeLine = getActiveLine()
      for (let i = 1; i <= lineCount; i++) {
        const div = document.createElement("div")
        div.className = i === activeLine ? "code-editor-line-num active" : "code-editor-line-num"
        div.dataset.line = String(i)
        div.textContent = String(i)
        fragment.appendChild(div)
      }
      lineNumbersEl.replaceChildren(fragment)
      renderedLineCount = lineCount
      currentActiveLine = activeLine
    } else {
      syncActiveLine()
    }

    lineNumbersEl.scrollTop = textarea.scrollTop
  }

  const updateStats = () => {
    if (!statsEl) return
    const val = textarea.value || ""
    const bytes = new Blob([val]).size
    const lines = val === "" ? 0 : val.split(/\r?\n/).length
    const maxBytes = parseInt(statsEl.dataset.maxBytes || "524288", 10)

    statsEl.textContent = `${lines} ${lines === 1 ? "line" : "lines"} · ${formatBytes(bytes)} / 512 KB`
    if (bytes > maxBytes) {
      statsEl.classList.add("text-rose-400", "font-semibold")
    } else {
      statsEl.classList.remove("text-rose-400", "font-semibold")
    }
  }

  const updateEditor = () => {
    updateStats()
    updateLineNumbers()
  }

  textarea.addEventListener("input", updateEditor)
  textarea.addEventListener("scroll", () => {
    if (lineNumbersEl) {
      lineNumbersEl.scrollTop = textarea.scrollTop
    }
  })
  textarea.addEventListener("click", syncActiveLine)
  textarea.addEventListener("keyup", syncActiveLine)
  textarea.addEventListener("select", syncActiveLine)
  textarea.addEventListener("focus", syncActiveLine)

  updateEditor()

  textarea.addEventListener("keydown", (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === "Enter") {
      e.preventDefault()
      textarea.closest("form")?.requestSubmit()
      return
    }

    if (e.key === "Tab") {
      e.preventDefault()
      const start = textarea.selectionStart
      const end = textarea.selectionEnd
      const value = textarea.value
      textarea.value = value.substring(0, start) + "  " + value.substring(end)
      textarea.selectionStart = textarea.selectionEnd = start + 2
      updateEditor()
    }
  })
}

document.addEventListener("click", async (e) => {
  const btn = e.target.closest("[data-copy-text], [data-copy-target]")
  if (!btn) return

  let textToCopy = btn.dataset.copyText
  if (!textToCopy && btn.dataset.copyTarget) {
    const target = document.querySelector(btn.dataset.copyTarget)
    if (target) textToCopy = target.value ?? target.textContent
  }

  if (typeof textToCopy === "string") {
    try {
      await navigator.clipboard.writeText(textToCopy)
      const label = btn.querySelector("[data-copy-label]") || btn
      const original = label.dataset.originalLabel || label.textContent
      label.dataset.originalLabel = original
      label.textContent = "Copied!"
      setTimeout(() => {
        label.textContent = original
      }, 1800)
    } catch (_err) {
      // Fallback if clipboard API is unavailable
    }
  }
})

window.addEventListener("DOMContentLoaded", initEditorEnhancements)
window.addEventListener("phx:page-loading-stop", initEditorEnhancements)
