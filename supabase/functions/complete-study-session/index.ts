import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { started_at: string; duration_seconds: number; mode: 'free_study' | 'ai_tutor' | 'quiz' | 'flashcards' | 'voice' | 'review'; subject_id?: string | null }
const allowedModes = new Set<Input['mode']>(['free_study', 'ai_tutor', 'quiz', 'flashcards', 'voice', 'review'])
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input || typeof input !== 'object' || typeof input.started_at !== 'string' || !input.started_at || !Number.isInteger(input.duration_seconds) || input.duration_seconds < 60 || input.duration_seconds > 86400 || !allowedModes.has(input.mode) || (input.subject_id !== undefined && input.subject_id !== null && !uuidPattern.test(input.subject_id))) throw new InputError('La sesión debe durar entre 1 minuto y 24 horas y tener datos válidos.')
    const startedAt = new Date(input.started_at)
    if (Number.isNaN(startedAt.valueOf())) throw new InputError('La sesión debe durar entre 1 minuto y 24 horas y tener datos válidos.')
    if (startedAt > new Date() || startedAt.getTime() + input.duration_seconds * 1000 > Date.now() + 120_000) throw new InputError('La duración no coincide con el horario de la sesión.')
    const { data, error } = await auth.admin.rpc('complete_study_session_atomic', { p_user_id: auth.user.id, p_subject_id: input.subject_id ?? null, p_started_at: startedAt.toISOString(), p_duration_seconds: input.duration_seconds, p_mode: input.mode })
    if (error) throw error
    return ok(data)
  } catch (error) { return asErrorResponse(error) }
})
