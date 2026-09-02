import { asErrorResponse, fail, InputError, jsonBody, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'

type Input = { source: 'task_completed' | 'study_session_completed' | 'exam_recorded'; source_id: string }
const rewards = { task_completed: 30, study_session_completed: 25, exam_recorded: 20 } as const


Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const input = await jsonBody<Input>(request)
    if (!input.source_id || !['task_completed', 'study_session_completed', 'exam_recorded'].includes(input.source)) throw new InputError('La actividad no es válida para obtener XP.')
    const table = input.source === 'task_completed' ? 'tasks' : input.source === 'study_session_completed' ? 'study_sessions' : 'exams'
    const { data: activity, error } = await auth.admin.from(table).select('*').eq('id', input.source_id).eq('user_id', auth.user.id).maybeSingle()
    if (error) throw error
    if (!activity) return fail('NOT_FOUND', 'No encontramos esa actividad.', 404)
    const completed = input.source === 'task_completed' ? activity.status === 'completed' : input.source === 'study_session_completed' ? activity.completed === true : activity.grade !== null
    if (!completed) return fail('INVALID_INPUT', 'Completá la actividad antes de pedir su recompensa.', 409)
    const { data: award, error: awardError } = await auth.admin.rpc('award_xp_internal', { p_user_id: auth.user.id, p_source: input.source, p_source_id: input.source_id, p_amount: rewards[input.source], p_description: 'Actividad académica completada' })
    if (awardError) throw awardError

    const countTable = input.source === 'task_completed' ? 'tasks' : input.source === 'exam_recorded' ? 'exams' : 'study_sessions'
    const { count } = await auth.admin.from(countTable).select('id', { count: 'exact', head: true }).eq('user_id', auth.user.id)
    const achievementCode = input.source === 'task_completed' && count === 1 ? 'first_task' : input.source === 'exam_recorded' && count === 1 ? 'first_exam' : input.source === 'study_session_completed' && count === 1 ? 'first_study' : null
    let achievement: { title: string; xp_reward: number } | null = null
    if (achievementCode) {
      const { data: definition } = await auth.admin.from('achievements').select('id,title,xp_reward').eq('code', achievementCode).maybeSingle()
      if (definition) {
        const { error: unlockError } = await auth.admin.from('user_achievements').insert({ user_id: auth.user.id, achievement_id: definition.id })
        if (!unlockError) { achievement = definition; await auth.admin.rpc('award_xp_internal', { p_user_id: auth.user.id, p_source: 'achievement_unlocked', p_source_id: definition.id, p_amount: definition.xp_reward, p_description: `Logro: ${definition.title}` }) }
      }
    }
    return ok({ awarded: award?.[0]?.awarded ?? false, amount: award?.[0]?.awarded ? rewards[input.source] : 0, current_streak: award?.[0]?.current_streak ?? 0, achievement })
  } catch (error) { return asErrorResponse(error) }
})
