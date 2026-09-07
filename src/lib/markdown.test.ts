import { describe, expect, it } from 'vitest'
import { renderMarkdown, renderMarkdownToHtml } from './markdown'

describe('markdown rendering library', () => {
  it('renders standard markdown elements to html', () => {
    const input = '### Explicación\n**Importante**: *concepto*\n- Punto 1\n- Punto 2'
    const html = renderMarkdown(input)
    expect(html).toContain('<h3>Explicación</h3>')
    expect(html).toContain('<strong>Importante</strong>')
    expect(html).toContain('<em>concepto</em>')
    expect(html).toContain('<li>Punto 1</li>')
  })

  it('renders inline KaTeX math formulas using $ or \\(', () => {
    const input = 'La fórmula de energía es $E = mc^2$ y también \\(a^2 + b^2 = c^2\\).'
    const html = renderMarkdown(input)
    expect(html).toContain('katex')
    expect(html).toContain('E = mc^2')
    expect(html).toContain('a^2 + b^2 = c^2')
  })

  it('renders block KaTeX math formulas using $$ or \\[\\]', () => {
    const input = 'Equivalencia:\n$$\n\\int_0^1 x dx = \\frac{1}{2}\n$$\ny además:\n\\[x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}\\]'
    const html = renderMarkdown(input)
    expect(html).toContain('katex-display')
    expect(html).toContain('\\int_0^1 x dx = \\frac{1}{2}')
  })

  it('preserves code blocks without attempting math replacement inside them', () => {
    const input = '```js\nconst price = $10;\nconst total = $20;\n```\nCódigo `$code` en línea.'
    const html = renderMarkdown(input)
    expect(html).toContain('<pre><code class="language-js">const price = $10;\nconst total = $20;\n</code></pre>')
    expect(html).toContain('<code>$code</code>')
  })

  it('handles links safely with external target attributes', () => {
    const input = '[Documentación](https://example.com)'
    const html = renderMarkdown(input)
    expect(html).toContain('target="_blank"')
    expect(html).toContain('rel="noopener noreferrer"')
  })

  it('handles empty or missing input gracefully', () => {
    expect(renderMarkdown('')).toBe('')
    expect(renderMarkdownToHtml('')).toBe('')
  })
})
