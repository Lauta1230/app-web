import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type SaveInput = { action: 'save'; exam_id?: string; title: string; subject_id?: string | null; scheduled_at?: string | null; grade?: number | null; max_grade?: number | null; passing_percentage: number; notes?: string | null }
type AwardInput = { action?: 'award'; exam_id: string }
type Input = SaveInput | AwardInput
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input || typeof input !== 'object') throw new InputError('Revisá los datos de la evaluación.')
    if (input.action !== 'save') {
      if (input.action !== undefined && input.action !== 'award') throw new InputError('La acción no es válida.')
      if (!uuidPattern.test(input.exam_id ?? '')) throw new InputError('Falta una evaluación válida.')
      const { data, error } = await auth.admin.rpc('award_xp_for_verified_event_atomic', { p_user_id: auth.user.id, p_source: 'exam_recorded', p_source_id: input.exam_id })
      if (error) throw error
      return ok(data)
    }
    const hasGrade = input.grade !== null && input.grade !== undefined
    if (typeof input.title !== 'string' || !input.title.trim() || input.title.trim().length > 180 || (input.exam_id !== undefined && !uuidPattern.test(input.exam_id)) || (input.subject_id !== undefined && input.subject_id !== null && !uuidPattern.test(input.subject_id)) || (input.scheduled_at !== undefined && input.scheduled_at !== null && typeof input.scheduled_at !== 'string') || typeof input.passing_percentage !== 'number' || !Number.isFinite(input.passing_percentage) || input.passing_percentage < 0 || input.passing_percentage > 100 || (input.notes !== undefined && input.notes !== null && typeof input.notes !== 'string') || (hasGrade && (typeof input.grade !== 'number' || !Number.isFinite(input.grade) || input.grade < 0 || typeof input.max_grade !== 'number' || !Number.isFinite(input.max_grade) || input.max_grade <= 0))) throw new InputError('Revisá los datos de la evaluación.')
    const scheduledAt = input.scheduled_at ? new Date(input.scheduled_at) : null
    if (scheduledAt && Number.isNaN(scheduledAt.valueOf())) throw new InputError('Revisá los datos de la evaluación.')
    const { data, error } = await auth.admin.rpc('save_exam_atomic', { p_user_id: auth.user.id, p_exam_id: input.exam_id ?? null, p_title: input.title.trim(), p_subject_id: input.subject_id ?? null, p_scheduled_at: scheduledAt?.toISOString() ?? null, p_grade: input.grade ?? null, p_max_grade: hasGrade ? input.max_grade : null, p_passing_percentage: input.passing_percentage, p_notes: input.notes?.trim() || null })
    if (error) throw error
    return ok(data)
  } catch (error) { return asErrorResponse(error) }
})
