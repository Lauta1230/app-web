import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { started_at: string; duration_seconds: number; mode: 'free_study' | 'ai_tutor' | 'quiz' | 'flashcards' | 'voice' | 'review'; subject_id?: string | null }
Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input.started_at || !Number.isInteger(input.duration_seconds) || input.duration_seconds < 60 || input.duration_seconds > 86400 || !['free_study', 'ai_tutor', 'quiz', 'flashcards', 'voice', 'review'].includes(input.mode)) throw new InputError('La sesión debe durar al menos un minuto y tener datos válidos.')
    if (input.subject_id) { const { data: subject } = await auth.admin.from('subjects').select('id').eq('id', input.subject_id).eq('user_id', auth.user.id).maybeSingle(); if (!subject) return fail('NOT_FOUND', 'No encontramos esa materia.', 404) }
    const started = new Date(input.started_at); if (Number.isNaN(started.valueOf()) || started > new Date()) throw new InputError('La hora de inicio no es válida.')
    const { data: session, error: sessionError } = await auth.admin.from('study_sessions').insert({ user_id: auth.user.id, subject_id: input.subject_id ?? null, started_at: started.toISOString(), ended_at: new Date().toISOString(), duration_seconds: input.duration_seconds, mode: input.mode, completed: true }).select('id,duration_seconds').single()
    if (sessionError || !session) throw sessionError ?? new Error('session missing')
    const { data: award, error: awardError } = await auth.admin.rpc('award_xp_internal', { p_user_id: auth.user.id, p_source: 'study_session_completed', p_source_id: session.id, p_amount: 25, p_description: 'Sesión de estudio completada' })
    if (awardError) throw awardError
    return ok({ session, xp_awarded: award?.[0]?.awarded ? 25 : 0 })
  } catch (error) { return asErrorResponse(error) }
})
