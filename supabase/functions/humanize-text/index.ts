import { AIService } from '../_shared/ai.ts'
import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { text: string; style: 'natural' | 'casual' | 'academic' | 'simple' }
const styles = { natural: 'natural y fluido', casual: 'casual pero respetuoso', academic: 'académico, claro y formal', simple: 'simple, directo y fácil de leer' }
Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input.text?.trim() || input.text.length > 12000 || !Object.hasOwn(styles, input.style)) throw new InputError('Ingresá un texto de hasta 12.000 caracteres y un estilo válido.')
    const text = await new AIService().tutor(`Reescribí el texto siguiente para mejorar claridad, fluidez y naturalidad en estilo ${styles[input.style]}. Conservá los hechos, no inventes citas o información y devolvé sólo la versión revisada.\n\n${input.text}`, 'Sos un asistente de redacción educativa en español. No ayudás a evadir detectores; priorizás que la persona entienda y revise su propio texto.')
    return ok({ text, style: input.style })
  } catch (error) {
    if (error instanceof Error && error.message === 'AI_UNAVAILABLE') return fail('AI_UNAVAILABLE', 'La herramienta de redacción no está disponible ahora. Intentá más tarde.', 503)
    return asErrorResponse(error)
  }
})
