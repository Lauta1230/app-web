import { render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { MarkdownMessage } from './MarkdownMessage'

describe('MarkdownMessage component', () => {
  it('renders formatted markdown text inside the component', () => {
    render(<MarkdownMessage content="**Respuesta de IA** sobre *matemáticas*" />)
    expect(screen.getByText('Respuesta de IA')).toBeDefined()
    expect(screen.getByText('matemáticas')).toBeDefined()
  })

  it('renders KaTeX math elements when content contains math notation', () => {
    const { container } = render(<MarkdownMessage content="Fórmula: $f(x) = x^2$" />)
    const katexEl = container.querySelector('.katex')
    expect(katexEl).not.toBeNull()
  })

  it('applies custom className when provided', () => {
    const { container } = render(<MarkdownMessage content="Texto" className="custom-class" />)
    const wrapper = container.querySelector('.markdown-content.custom-class')
    expect(wrapper).not.toBeNull()
  })
})
