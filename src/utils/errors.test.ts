import { describe, expect, it } from 'vitest'
import { friendlyError } from './errors'

describe('friendlyError', () => {
  it('never passes technical auth messages through to a student', () => {
    expect(friendlyError(new Error('Invalid login credentials'))).toBe('El email o la contraseña no son correctos.')
  })
  it('uses a helpful connection fallback', () => {
    expect(friendlyError(new Error('fetch failed'))).toContain('conectarnos')
  })
})
