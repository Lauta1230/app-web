import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { action?: 'list' | 'mark_read'; notification_id?: string }
Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input.action || input.action === 'list') {
      const { data, error } = await auth.admin.from('notifications').select('id,title,body,read_at,created_at').eq('user_id', auth.user.id).order('created_at', { ascending: false }).limit(30)
      if (error) throw error
      return ok({ notifications: data ?? [] })
    }
    if (input.action !== 'mark_read' || !input.notification_id) throw new InputError('La notificación no es válida.')
    const { data, error } = await auth.admin.from('notifications').update({ read_at: new Date().toISOString() }).eq('id', input.notification_id).eq('user_id', auth.user.id).select().maybeSingle()
    if (error) throw error
    if (!data) return fail('NOT_FOUND', 'No encontramos esa notificación.', 404)
    return ok({ notification: data })
  } catch (error) { return asErrorResponse(error) }
})
