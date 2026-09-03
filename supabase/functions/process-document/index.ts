import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { document_id: string; name: string; document_type: 'note' | 'exam' | 'task' | 'document'; subject_id?: string | null; corrected_text?: string }
Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input.document_id || !input.name?.trim() || input.name.trim().length > 255 || !['note', 'exam', 'task', 'document'].includes(input.document_type) || (input.corrected_text?.length ?? 0) > 30000) throw new InputError('Revisá los datos confirmados del documento.')
    if (input.subject_id) {
      const { data: subject } = await auth.admin.from('subjects').select('id').eq('id', input.subject_id).eq('user_id', auth.user.id).maybeSingle()
      if (!subject) return fail('NOT_FOUND', 'No encontramos esa materia.', 404)
    }
    const { data: document, error } = await auth.admin.from('documents').update({ name: input.name.trim(), document_type: input.document_type, subject_id: input.subject_id ?? null, extracted_text: input.corrected_text ?? undefined, confirmed_at: new Date().toISOString() }).eq('id', input.document_id).eq('user_id', auth.user.id).eq('processing_status', 'completed').select().maybeSingle()
    if (error) throw error
    if (!document) return fail('NOT_FOUND', 'El documento no está listo para confirmar o no te pertenece.', 404)
    return ok({ document })
  } catch (error) { return asErrorResponse(error) }
})
