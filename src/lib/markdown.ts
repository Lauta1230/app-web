import { marked } from 'marked'
import katex from 'katex'

const renderer = new marked.Renderer()
renderer.link = ({ href, title, text }) => {
  const titleAttr = title ? ` title="${title}"` : ''
  return `<a href="${href}"${titleAttr} target="_blank" rel="noopener noreferrer">${text}</a>`
}

marked.setOptions({
  renderer,
  gfm: true,
  breaks: true,
})

export function renderMarkdown(text: string): string {
  if (!text) return ''

  const codeBlocks: { key: string; value: string }[] = []
  let placeholderCount = 0

  let processed = text.replace(/(```[\s\S]*?```|~~~[\s\S]*?~~~)/g, (match) => {
    const key = `__CODE_BLOCK_${placeholderCount++}__`
    codeBlocks.push({ key, value: match })
    return key
  })

  processed = processed.replace(/`([^`\n]+)`/g, (match) => {
    const key = `__INLINE_CODE_${placeholderCount++}__`
    codeBlocks.push({ key, value: match })
    return key
  })

  processed = processed.replace(/\\\[([\s\S]*?)\\\]/g, (_, math: string) => `$$${math}$$`)
  processed = processed.replace(/\\\(([\s\S]*?)\\\)/g, (_, math: string) => `$${math}$`)

  processed = processed.replace(/\$\$([\s\S]*?)\$\$/g, (match, math: string) => {
    try {
      return katex.renderToString(math.trim(), { displayMode: true, throwOnError: false })
    } catch {
      return match
    }
  })

  processed = processed.replace(/(?<!\\)\$([^$\n]+?)\$/g, (match, math: string) => {
    try {
      return katex.renderToString(math.trim(), { displayMode: false, throwOnError: false })
    } catch {
      return match
    }
  })

  for (const item of codeBlocks) {
    processed = processed.replace(item.key, item.value)
  }

  const parsed = marked.parse(processed)
  return typeof parsed === 'string' ? parsed : String(parsed)
}

export function renderMarkdownToHtml(text: string): string {
  return renderMarkdown(text)
}
