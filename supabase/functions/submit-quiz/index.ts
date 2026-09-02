import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type SubmitInput = { quiz_id: string; answers: Array<{ question_id: string; answer: string }> }
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<SubmitInput>(request)
    if (!input || typeof input !== 'object' || !uuidPattern.test(input.quiz_id ?? '') || !Array.isArray(input.answers) || input.answers.length < 1 || input.answers.length > 20 || input.answers.some((item) => !item || typeof item !== 'object' || !uuidPattern.test(item.question_id ?? '') || typeof item.answer !== 'string' || item.answer.length > 5000)) throw new InputError('Las respuestas del quiz no son válidas.')
    if (new Set(input.answers.map((answer) => answer.question_id)).size !== input.answers.length) throw new InputError('Hay preguntas respondidas más de una vez.')
    // All state-changing operations occur inside one PostgreSQL transaction.
    const { data, error } = await auth.admin.rpc('submit_quiz_atomic', { p_user_id: auth.user.id, p_quiz_id: input.quiz_id, p_answers: input.answers })
    if (error) throw error
    return ok(data)
  } catch (error) { return asErrorResponse(error) }
})
