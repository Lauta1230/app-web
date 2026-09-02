import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { source: 'task_completed' | 'study_session_completed' | 'quiz_completed' | 'exam_recorded'; source_id: string }
const validSources = new Set<Input['source']>(['task_completed', 'study_session_completed', 'quiz_completed', 'exam_recorded'])
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input || typeof input !== 'object' || !uuidPattern.test(input.source_id ?? '') || !validSources.has(input.source)) throw new InputError('La actividad no es válida para obtener XP.')
    // The RPC verifies the source state under a row lock and only uses fixed rewards.
    const { data, error } = await auth.admin.rpc('award_xp_for_verified_event_atomic', { p_user_id: auth.user.id, p_source: input.source, p_source_id: input.source_id })
    if (error) throw error
    return ok(data)
  } catch (error) { return asErrorResponse(error) }
})
