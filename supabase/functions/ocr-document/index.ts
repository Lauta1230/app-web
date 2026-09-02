import { AIService } from '../_shared/ai.ts'
import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'
import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { document_id: string }
Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  let documentId: string | null = null
  let admin: SupabaseClient | null = null
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    admin = auth.admin
    const input = await jsonBody<Input>(request)
    if (!input.document_id) throw new InputError('Elegí un documento para escanear.')
    documentId = input.document_id
    const { data: document, error } = await admin.from('documents').select('*').eq('id', documentId).eq('user_id', auth.user.id).maybeSingle()
    if (error) throw error
    if (!document) return fail('NOT_FOUND', 'No encontramos ese documento.', 404)
    if (!['application/pdf', 'image/jpeg', 'image/png', 'image/webp', 'text/plain'].includes(document.mime_type)) throw new InputError('Este tipo de archivo no puede analizarse.')
    await admin.from('documents').update({ processing_status: 'processing', error_message: null }).eq('id', document.id)
    const { data: file, error: downloadError } = await admin.storage.from('documents').download(document.storage_path)
    if (downloadError || !file) throw downloadError ?? new Error('file missing')
    const source = new Uint8Array(await file.arrayBuffer())
    const extractedText = await new AIService().image(source, document.mime_type, 'Extraé el texto visible de este documento en español. Luego agregá en líneas separadas: TIPO SUGERIDO: apunte, evaluación, tarea o documento; MATERIA SUGERIDA: si se infiere; FECHA SUGERIDA: si existe; NOTA SUGERIDA: si existe. Si no podés inferir un dato, escribí "No detectado". No inventes información.')
    const detectedType = /TIPO SUGERIDO:\s*(evaluación|tarea|apunte|documento)/i.exec(extractedText)?.[1]?.toLowerCase()
    const type = detectedType === 'evaluación' ? 'exam' : detectedType === 'tarea' ? 'task' : detectedType === 'apunte' ? 'note' : 'document'
    const { data: updated, error: updateError } = await admin.from('documents').update({ processing_status: 'completed', document_type: type, extracted_text: extractedText, extracted_data: { requires_confirmation: true } }).eq('id', document.id).eq('user_id', auth.user.id).select().single()
    if (updateError) throw updateError
    return ok({ document: updated, requires_confirmation: true })
  } catch (error) {
    if (documentId && admin) await admin.from('documents').update({ processing_status: 'failed', error_message: 'No pudimos analizar el archivo. Podés reintentar.' }).eq('id', documentId)
    const message = error instanceof Error ? error.message : ''
    if (message === 'AI_UNAVAILABLE') return fail('AI_UNAVAILABLE', 'No pudimos analizar el documento ahora. Tu archivo sigue guardado y podés reintentar.', 503)
    if (message === 'AI_RATE_LIMIT') return fail('AI_RATE_LIMIT', 'La IA alcanzó temporalmente su límite gratuito. Intentá nuevamente más tarde.', 429)
    return asErrorResponse(error)
  }
})
