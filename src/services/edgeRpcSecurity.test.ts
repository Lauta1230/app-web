import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { describe, expect, it } from 'vitest'

const rpcFunctions = [
  { file: 'complete-task', rpc: 'complete_task_atomic' },
  { file: 'complete-study-session', rpc: 'complete_study_session_atomic' },
  { file: 'process-exam', rpc: 'save_exam_atomic' },
  { file: 'submit-quiz', rpc: 'submit_quiz_atomic' },
  { file: 'award-xp', rpc: 'award_xp_for_verified_event_atomic' },
] as const

function sourceFor(name: string): string {
  return readFileSync(resolve(process.cwd(), 'supabase', 'functions', name, 'index.ts'), 'utf8')
}

describe('Edge RPC authority boundary', () => {
  it.each(rpcFunctions)('$file derives p_user_id from the verified JWT', ({ file, rpc }) => {
    const source = sourceFor(file)
    const requireUserAt = source.indexOf('requireUser(request)')
    const bodyAt = source.indexOf('jsonBody<')
    const rpcAt = source.indexOf(`rpc('${rpc}'`)

    expect(requireUserAt).toBeGreaterThan(-1)
    expect(bodyAt).toBeGreaterThan(requireUserAt)
    expect(rpcAt).toBeGreaterThan(bodyAt)
    expect(source).toMatch(/p_user_id:\s*auth\.user\.id/)
    expect(source).not.toMatch(/input\.user_id|body\.user_id|p_user_id:\s*input/)
  })

  it('does not expose a client-supplied task owner in the task creation API', () => {
    const api = readFileSync(resolve(process.cwd(), 'src', 'services', 'api.ts'), 'utf8')
    const taskApi = api.slice(api.indexOf('export const tasksApi'), api.indexOf('export const eventsApi'))

    expect(taskApi).toContain("rpc('create_task_atomic'")
    expect(taskApi).not.toMatch(/async create\(userId/)
    expect(taskApi).not.toMatch(/user_id:\s*userId/)
  })
})
