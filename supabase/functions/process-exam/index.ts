import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { exam_id: string }
Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input.exam_id) throw new InputError('Falta la evaluación a procesar.')
    const { data: exam, error } = await auth.admin.from('exams').select('id,title,grade,max_grade,percentage,status').eq('id', input.exam_id).eq('user_id', auth.user.id).maybeSingle()
    if (error) throw error
    if (!exam) return fail('NOT_FOUND', 'No encontramos esa evaluación.', 404)
    if (exam.grade === null || exam.max_grade === null) return fail('INVALID_INPUT', 'Ingresá la nota y la nota máxima antes de procesar.', 409)
    const { data: award, error: awardError } = await auth.admin.rpc('award_xp_internal', { p_user_id: auth.user.id, p_source: 'exam_recorded', p_source_id: exam.id, p_amount: 20, p_description: `Evaluación registrada: ${exam.title}` })
    if (awardError) throw awardError
    return ok({ exam, xp_awarded: award?.[0]?.awarded ? 20 : 0 })
  } catch (error) { return asErrorResponse(error) }
})
