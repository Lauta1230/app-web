import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { task_id: string }
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input || typeof input !== 'object' || !uuidPattern.test(input.task_id ?? '')) throw new InputError('Falta una tarea válida para completar.')
    // The database function locks the task, enforces the pending→completed transition,
    // writes the idempotent ledger entry, updates the streak and checks achievements
    // in one database transaction.
    const { data, error } = await auth.admin.rpc('complete_task_atomic', { p_user_id: auth.user.id, p_task_id: input.task_id })
    if (error) throw error
    return ok(data)
  } catch (error) { return asErrorResponse(error) }
})
