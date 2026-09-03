import { describe, expect, it } from 'vitest'
import { AppError, friendlyError } from './errors'

describe('friendlyError', () => {
  it('never passes technical auth messages through to a student', () => {
    expect(friendlyError(new Error('Invalid login credentials'))).toBe('El email o la contraseña no son correctos.')
  })
  it('uses a helpful connection fallback', () => {
    expect(friendlyError(new Error('fetch failed'))).toContain('conectarnos')
  })
  it('maps DASHBOARD_UNAVAILABLE to a safe, retryable message', () => {
    expect(friendlyError(new AppError('DASHBOARD_UNAVAILABLE', 'raw'))).toContain('panel')
  })
})
