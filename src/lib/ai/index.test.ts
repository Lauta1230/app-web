import { describe, expect, it } from 'vitest'
import { AIResponseValidator } from './index'

describe('AIResponseValidator', () => {
  it('accepts only the expected number of persisted questions', () => {
    expect(AIResponseValidator.quizCount([{ id: 'q1', position: 1, question_type: 'multiple_choice', prompt: '¿Pregunta?', options: ['A'] }], 1)).toBe(true)
  })
  it('rejects incomplete or mismatched AI output', () => {
    expect(AIResponseValidator.quizCount([{ id: '', position: 1, question_type: 'multiple_choice', prompt: '', options: null }], 1)).toBe(false)
    expect(AIResponseValidator.quizCount([], 2)).toBe(false)
  })
})
