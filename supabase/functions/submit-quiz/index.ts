import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type SubmitInput = { quiz_id: string; answers: Array<{ question_id: string; answer: string }> }
const normalize = (value: string) => value.trim().toLocaleLowerCase().replace(/\s+/g, ' ')

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<SubmitInput>(request)
    if (!input.quiz_id || !Array.isArray(input.answers) || input.answers.length > 20 || input.answers.some((item) => !item.question_id || typeof item.answer !== 'string' || item.answer.length > 5000)) throw new InputError('Las respuestas del quiz no son válidas.')
    if (new Set(input.answers.map((answer) => answer.question_id)).size !== input.answers.length) throw new InputError('Hay preguntas respondidas más de una vez.')
    const { data: quiz } = await auth.admin.from('quizzes').select('id,status').eq('id', input.quiz_id).eq('user_id', auth.user.id).maybeSingle()
    if (!quiz) return fail('NOT_FOUND', 'No encontramos ese quiz.', 404)
    if (quiz.status === 'completed') return fail('INVALID_INPUT', 'Este quiz ya fue enviado.', 409)
    if (quiz.status !== 'active') return fail('INVALID_INPUT', 'Este quiz no está disponible.', 409)
    const { data: questions, error } = await auth.admin.from('quiz_questions').select('id,prompt,quiz_answer_keys(accepted_answers,explanation)').eq('quiz_id', quiz.id).order('position')
    if (error || !questions?.length) throw error ?? new Error('quiz questions not found')
    if (input.answers.length !== questions.length) throw new InputError('Respondé todas las preguntas antes de enviar el quiz.')
    const received = new Map(input.answers.map((answer) => [answer.question_id, answer.answer]))
    if (questions.some((question) => !received.has(question.id))) throw new InputError('Una o más preguntas no pertenecen a este quiz.')
    const answerRows = questions.map((question) => {
      const keys = question.quiz_answer_keys as unknown as Array<{ accepted_answers: string[]; explanation: string | null }>
      const answer = received.get(question.id) ?? ''
      const isCorrect = keys?.[0]?.accepted_answers.some((accepted) => normalize(accepted) === normalize(answer)) ?? false
      return { quiz_id: quiz.id, question_id: question.id, answer, is_correct: isCorrect, feedback: isCorrect ? '¡Correcto!' : keys?.[0]?.explanation ?? 'Repasá este concepto y volvé a intentarlo.' }
    })
    const correct = answerRows.filter((answer) => answer.is_correct).length
    const score = Math.round((correct / questions.length) * 100)
    const { error: answerError } = await auth.admin.from('quiz_answers').insert(answerRows)
    if (answerError) throw answerError
    const { error: updateError } = await auth.admin.from('quizzes').update({ status: 'completed', score, completed_at: new Date().toISOString() }).eq('id', quiz.id).eq('status', 'active')
    if (updateError) throw updateError
    const xp = 20 + correct * 5
    const { data: award, error: awardError } = await auth.admin.rpc('award_xp_internal', { p_user_id: auth.user.id, p_source: 'quiz_completed', p_source_id: quiz.id, p_amount: xp, p_description: `Quiz completado: ${score}%` })
    if (awardError) throw awardError
    return ok({ score, correct_answers: correct, question_count: questions.length, xp_awarded: award?.[0]?.awarded ? xp : 0, answers: answerRows.map(({ question_id, is_correct, feedback }) => ({ question_id, is_correct, feedback })) })
  } catch (error) { return asErrorResponse(error) }
})
