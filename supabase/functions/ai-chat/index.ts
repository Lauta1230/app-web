import { AIContextBuilder, AIService } from '../_shared/ai.ts'
import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type ChatInput = { message: string; conversation_id?: string; subject_id?: string; note_id?: string; document_id?: string; mode?: 'Explicame' | 'Preguntame' | 'Examiname' | 'Repasemos' | 'Voz' }

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<ChatInput>(request)
    const message = input.message?.trim()
    if (!message || message.length > 6000) throw new InputError('Escribí un mensaje de hasta 6.000 caracteres.')
    if (input.subject_id && !(await auth.admin.from('subjects').select('id,name').eq('id', input.subject_id).eq('user_id', auth.user.id).maybeSingle()).data) return fail('NOT_FOUND', 'No encontramos esa materia.', 404)
    if (input.note_id && !(await auth.admin.from('notes').select('id').eq('id', input.note_id).eq('user_id', auth.user.id).maybeSingle()).data) return fail('NOT_FOUND', 'No encontramos ese apunte.', 404)
    if (input.document_id && !(await auth.admin.from('documents').select('id').eq('id', input.document_id).eq('user_id', auth.user.id).eq('processing_status', 'completed').not('confirmed_at', 'is', null).maybeSingle()).data) return fail('NOT_FOUND', 'Confirmá primero el documento que querés usar.', 404)

    let conversationId = input.conversation_id
    if (conversationId) {
      const { data } = await auth.admin.from('ai_conversations').select('id').eq('id', conversationId).eq('user_id', auth.user.id).maybeSingle()
      if (!data) return fail('NOT_FOUND', 'No encontramos esa conversación.', 404)
    } else {
      const { data, error } = await auth.admin.from('ai_conversations').insert({ user_id: auth.user.id, subject_id: input.subject_id ?? null, note_id: input.note_id ?? null, mode: 'ai_tutor', title: message.slice(0, 70) }).select('id').single()
      if (error || !data) throw error ?? new Error('conversation creation failed')
      conversationId = data.id
    }
    const [{ data: profile }, { data: subject }, { data: note }, { data: document }, { data: history }] = await Promise.all([
      auth.admin.from('profiles').select('display_name,education_level,ai_personality').eq('id', auth.user.id).single(),
      input.subject_id ? auth.admin.from('subjects').select('name').eq('id', input.subject_id).single() : Promise.resolve({ data: null }),
      input.note_id ? auth.admin.from('notes').select('content').eq('id', input.note_id).single() : Promise.resolve({ data: null }),
      input.document_id ? auth.admin.from('documents').select('name,extracted_text').eq('id', input.document_id).single() : Promise.resolve({ data: null }),
      auth.admin.from('ai_messages').select('role,content').eq('conversation_id', conversationId).order('created_at', { ascending: false }).limit(8)
    ])
    await auth.admin.from('ai_messages').insert({ conversation_id: conversationId, role: 'user', content: message })
    const previous = (history ?? []).reverse().map((entry) => `${entry.role === 'assistant' ? 'Tutor' : 'Estudiante'}: ${entry.content}`).join('\n')
    const context = AIContextBuilder.tutor({ displayName: profile?.display_name, educationLevel: profile?.education_level, personality: profile?.ai_personality, subject: subject?.name, mode: input.mode, note: [note?.content, document?.extracted_text ? `Documento seleccionado: ${document.name}\n${document.extracted_text}` : null].filter(Boolean).join('\n\n') })
    const answer = await new AIService().tutor(`Historial breve:\n${previous || '(sin historial)'}\n\nMensaje actual del estudiante: ${message}`, context)
    const { error: messageError } = await auth.admin.from('ai_messages').insert({ conversation_id: conversationId, role: 'assistant', content: answer })
    if (messageError) throw messageError
    await auth.admin.from('ai_conversations').update({ updated_at: new Date().toISOString() }).eq('id', conversationId)
    await auth.admin.rpc('award_xp_internal', { p_user_id: auth.user.id, p_source: 'study_session_completed', p_source_id: conversationId, p_amount: 10, p_description: 'Primera interacción de estudio con IA' })
    return ok({ conversation_id: conversationId, message: answer })
  } catch (error) {
    if (error instanceof Error && error.message === 'AI_UNAVAILABLE') return fail('AI_UNAVAILABLE', 'La IA no está disponible en este momento. Podés seguir estudiando con tus apuntes y tareas.', 503)
    return asErrorResponse(error)
  }
})
