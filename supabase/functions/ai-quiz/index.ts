import { AIContextBuilder, AIResponseValidator, AIService } from '../_shared/ai.ts'
import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type QuizInput = { subject_id: string; topic: string; difficulty: 'easy' | 'normal' | 'hard'; question_count: number; source_text?: string }
type GeneratedQuiz = { title: string; questions: Array<{ type: string; prompt: string; options?: string[]; answers: string[]; explanation?: string }> }
const allowedTypes = new Set(['multiple_choice', 'true_false', 'short_answer', 'open_answer', 'oral'])

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<QuizInput>(request)
    if (!input.subject_id || !input.topic?.trim() || !['easy', 'normal', 'hard'].includes(input.difficulty) || !Number.isInteger(input.question_count) || input.question_count < 1 || input.question_count > 20) throw new InputError('Revisá materia, tema, dificultad y cantidad (entre 1 y 20).')
    if ((input.source_text?.length ?? 0) > 24000) throw new InputError('El material para el quiz es demasiado extenso.')
    const { data: subject } = await auth.admin.from('subjects').select('id,name').eq('id', input.subject_id).eq('user_id', auth.user.id).maybeSingle()
    if (!subject) return fail('NOT_FOUND', 'No encontramos esa materia.', 404)
    const { data: profile } = await auth.admin.from('profiles').select('education_level,ai_personality').eq('id', auth.user.id).single()
    const schema = {
      type: 'object', properties: { title: { type: 'string' }, questions: { type: 'array', minItems: input.question_count, maxItems: input.question_count, items: { type: 'object', properties: { type: { type: 'string', enum: [...allowedTypes] }, prompt: { type: 'string' }, options: { type: 'array', items: { type: 'string' } }, answers: { type: 'array', minItems: 1, items: { type: 'string' } }, explanation: { type: 'string' } }, required: ['type', 'prompt', 'answers'] } } }, required: ['title', 'questions']
    }
    const prompt = `Creá exactamente ${input.question_count} preguntas de quiz sobre "${input.topic.trim()}" para ${subject.name}. Dificultad: ${input.difficulty}. Para multiple_choice usá 4 opciones y guardá como respuesta la letra A, B, C o D. Para true_false, opciones Verdadero/Falso. Las respuestas deben ser breves y evaluables. Material de referencia (si está disponible):\n${input.source_text?.trim() || 'No hay material: no inventes datos específicos; formulá preguntas generales y aclarables.'}`
    const generated = await new AIService().structured<GeneratedQuiz>(prompt, schema, AIContextBuilder.tutor({ educationLevel: profile?.education_level, personality: profile?.ai_personality, subject: subject.name, mode: 'Examiname' }))
    if (!AIResponseValidator.quiz(generated) || generated.questions.length !== input.question_count || generated.questions.some((question) => !allowedTypes.has(question.type))) throw new InputError('La IA no pudo crear un quiz con formato seguro. Intentá nuevamente.')
    const { data: quiz, error: quizError } = await auth.admin.from('quizzes').insert({ user_id: auth.user.id, subject_id: subject.id, title: generated.title.slice(0, 180), topic: input.topic.trim(), difficulty: input.difficulty, status: 'active', started_at: new Date().toISOString() }).select('id,title,difficulty').single()
    if (quizError || !quiz) throw quizError ?? new Error('quiz creation failed')
    const publicQuestions = generated.questions.map((question, index) => ({ quiz_id: quiz.id, position: index + 1, question_type: question.type, prompt: question.prompt.slice(0, 5000), options: question.options ?? null }))
    const { data: persistedQuestions, error: questionError } = await auth.admin.from('quiz_questions').insert(publicQuestions).select('id,position,question_type,prompt,options')
    if (questionError || !persistedQuestions) { await auth.admin.from('quizzes').delete().eq('id', quiz.id); throw questionError ?? new Error('questions failed') }
    const keys = persistedQuestions.map((question) => ({ question_id: question.id, accepted_answers: generated.questions[question.position - 1].answers.map((answer) => answer.trim().toLowerCase()), explanation: generated.questions[question.position - 1].explanation?.slice(0, 5000) ?? null }))
    const { error: keysError } = await auth.admin.from('quiz_answer_keys').insert(keys)
    if (keysError) { await auth.admin.from('quizzes').delete().eq('id', quiz.id); throw keysError }
    return ok({ quiz_id: quiz.id, title: quiz.title, difficulty: quiz.difficulty, questions: persistedQuestions })
  } catch (error) {
    if (error instanceof Error && error.message === 'AI_UNAVAILABLE') return fail('AI_UNAVAILABLE', 'La IA no está disponible en este momento. Intentá crear el quiz más tarde.', 503)
    return asErrorResponse(error)
  }
})
