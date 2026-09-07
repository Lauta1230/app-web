import { renderMarkdown } from '../lib/markdown'

export interface MarkdownMessageProps {
  content: string
  className?: string
}

export function MarkdownMessage({ content, className = '' }: MarkdownMessageProps) {
  const html = renderMarkdown(content)

  return (
    <div
      className={`markdown-content ${className}`.trim()}
      dangerouslySetInnerHTML={{ __html: html }}
    />
  )
}
