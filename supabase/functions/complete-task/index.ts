import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { task_id: string }
Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request); if (!input.task_id) throw new InputError('Falta la tarea a completar.')
    const { data: existing } = await auth.admin.from('tasks').select('id,status').eq('id', input.task_id).eq('user_id', auth.user.id).maybeSingle()
    if (!existing) return fail('NOT_FOUND', 'No encontramos esa tarea.', 404)
    const { data: task, error: updateError } = await auth.admin.from('tasks').update({ status: 'completed', completed_at: new Date().toISOString() }).eq('id', input.task_id).eq('user_id', auth.user.id).select().single()
    if (updateError) throw updateError
    const { data: award, error: awardError } = await auth.admin.rpc('award_xp_internal', { p_user_id: auth.user.id, p_source: 'task_completed', p_source_id: task.id, p_amount: 30, p_description: `Tarea completada: ${task.title}` })
    if (awardError) throw awardError
    return ok({ task, xp_awarded: award?.[0]?.awarded ? 30 : 0, current_streak: award?.[0]?.current_streak ?? 0 })
  } catch (error) { return asErrorResponse(error) }
})
