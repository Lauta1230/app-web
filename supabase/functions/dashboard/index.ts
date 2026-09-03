import { fail, ok, options } from '../_shared/http.ts'
import { isResponse, requireUser } from '../_shared/supabase.ts'
import { studyRecommendation } from '../_shared/recommendation.ts'

type QueryError = { message: string } | null
function check(error: QueryError, operation: string): void {
  if (error) throw new Error(`${operation}: ${error.message}`)
}

Deno.serve(async (request) => {
  const preflight = options(request); if (preflight) return preflight
  if (request.method !== 'POST') return fail('INVALID_INPUT', 'Método no permitido.', 405)
  try {
    const auth = await requireUser(request); if (isResponse(auth)) return auth
    const todayStart = new Date(); todayStart.setHours(0, 0, 0, 0)
    const tomorrow = new Date(todayStart); tomorrow.setDate(tomorrow.getDate() + 1)
    const [profileRes, streakRes, petRes, xpRes, todayTasksRes, todayEventsRes, sessionsRes, upcomingExamsRes, recentTasksRes, recommendation] = await Promise.all([
      auth.admin.from('profiles').select('display_name,education_level,ai_personality,onboarding_completed').eq('id', auth.user.id).maybeSingle(),
      auth.admin.from('streaks').select('current_streak,longest_streak,last_activity_date').eq('user_id', auth.user.id).maybeSingle(),
      auth.admin.from('pets').select('id,name,species,level,happiness,energy').eq('user_id', auth.user.id).maybeSingle(),
      auth.admin.from('xp_transactions').select('amount').eq('user_id', auth.user.id),
      auth.admin.from('tasks').select('id,title,priority,due_at,status,subject_id,subjects(name,color)').eq('user_id', auth.user.id).eq('status', 'pending').lt('due_at', tomorrow.toISOString()).order('due_at').limit(6),
      auth.admin.from('calendar_events').select('id,title,event_type,starts_at,duration_minutes,subject_id,subjects(name,color)').eq('user_id', auth.user.id).gte('starts_at', todayStart.toISOString()).lt('starts_at', tomorrow.toISOString()).order('starts_at').limit(6),
      auth.admin.from('study_sessions').select('id,started_at,ended_at,duration_seconds,mode,completed,subject_id').eq('user_id', auth.user.id).gte('started_at', todayStart.toISOString()).order('started_at'),
      auth.admin.from('exams').select('id,title,scheduled_at,subject_id,subjects(name,color)').eq('user_id', auth.user.id).eq('status', 'pending').gte('scheduled_at', todayStart.toISOString()).order('scheduled_at').limit(4),
      auth.admin.from('tasks').select('id,title,status,completed_at,updated_at').eq('user_id', auth.user.id).order('updated_at', { ascending: false }).limit(5),
      studyRecommendation(auth.admin, auth.user.id)
    ])
    check(profileRes.error, 'profiles')
    check(streakRes.error, 'streaks')
    check(petRes.error, 'pets')
    check(xpRes.error, 'xp_transactions')
    check(todayTasksRes.error, 'tasks')
    check(todayEventsRes.error, 'calendar_events')
    check(sessionsRes.error, 'study_sessions')
    check(upcomingExamsRes.error, 'exams')
    check(recentTasksRes.error, 'recent tasks')
    const totalXp = (xpRes.data ?? []).reduce((total, item) => total + Number(item.amount), 0)
    const { data: level, error: levelError } = await auth.admin.from('levels').select('id,name,min_xp').lte('min_xp', totalXp).order('min_xp', { ascending: false }).limit(1).maybeSingle()
    check(levelError, 'levels')
    const { data: nextLevel, error: nextLevelError } = await auth.admin.from('levels').select('id,name,min_xp').gt('min_xp', totalXp).order('min_xp').limit(1).maybeSingle()
    check(nextLevelError, 'next level')
    const activeLevel = level ?? { id: 1, name: 'Principiante', min_xp: 0 }
    return ok({ profile: profileRes.data, streak: streakRes.data ?? { current_streak: 0, longest_streak: 0 }, level: { ...activeLevel, xp: totalXp, next_level: nextLevel }, pet: petRes.data, today: { tasks: todayTasksRes.data ?? [], events: todayEventsRes.data ?? [], study_sessions: sessionsRes.data ?? [] }, upcoming_exams: upcomingExamsRes.data ?? [], recommendation, recent_activity: recentTasksRes.data ?? [] })
  } catch (error) {
    console.error('Dashboard unavailable', error)
    return fail('DASHBOARD_UNAVAILABLE', 'El panel no está disponible en este momento. Tus datos están a salvo; reintentá en unos minutos.', 503)
  }
})
