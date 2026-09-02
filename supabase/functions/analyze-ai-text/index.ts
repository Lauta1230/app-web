import { AIService } from '../_shared/ai.ts'
import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { text: string }
type Analysis = { summary: string; signals: Array<{ label: string; detail: string; level: 'low' | 'medium' | 'high' }>; suggestions: string[] }
const schema = { type: 'object', properties: { summary: { type: 'string' }, signals: { type: 'array', maxItems: 5, items: { type: 'object', properties: { label: { type: 'string' }, detail: { type: 'string' }, level: { type: 'string', enum: ['low', 'medium', 'high'] } }, required: ['label', 'detail', 'level'] } }, suggestions: { type: 'array', maxItems: 5, items: { type: 'string' } } }, required: ['summary', 'signals', 'suggestions'] }
Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input.text?.trim() || input.text.length > 12000) throw new InputError('Ingresá un texto de hasta 12.000 caracteres.')
    const analysis = await new AIService().structured<Analysis>(`Analizá el texto únicamente como una revisión de estilo. Identificá señales compatibles con uniformidad excesiva, falta de ejemplos personales, repeticiones o tono poco natural. No afirmes ni calcules porcentajes de autoría de IA y no des consejos para evadir detectores. Devolvé sugerencias concretas para que el autor lo revise.\n\nTexto:\n${input.text}`, schema, 'Sos un revisor educativo prudente. El análisis es estimativo, no forense ni definitivo.')
    return ok({ ...analysis, disclaimer: 'Este análisis es estimativo y no puede determinar con certeza si un texto fue generado por IA.' })
  } catch (error) {
    if (error instanceof Error && error.message === 'AI_UNAVAILABLE') return fail('AI_UNAVAILABLE', 'El análisis no está disponible ahora. Intentá más tarde.', 503)
    return asErrorResponse(error)
  }
})
