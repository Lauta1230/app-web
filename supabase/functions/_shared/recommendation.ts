import type { SupabaseClient } from 'npm:@supabase/supabase-js@2'

export type StudyRecommendation = { subject_id: string | null; subject_name: string | null; topic: string; duration_minutes: number; reason: string; action: string } | null

export async function studyRecommendation(admin: SupabaseClient, userId: string): Promise<StudyRecommendation> {
  const now = new Date()
  const inSevenDays = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000).toISOString()
  const [{ data: exams }, { data: tasks }, { data: grades }] = await Promise.all([
    admin.from('exams').select('id,title,subject_id,scheduled_at,subjects(name)').eq('user_id', userId).eq('status', 'pending').gte('scheduled_at', now.toISOString()).lte('scheduled_at', inSevenDays).order('scheduled_at').limit(1),
    admin.from('tasks').select('id,title,subject_id,due_at,subjects(name)').eq('user_id', userId).eq('status', 'pending').gte('due_at', now.toISOString()).lte('due_at', inSevenDays).order('due_at').limit(1),
    admin.from('exams').select('subject_id,percentage,subjects(name)').eq('user_id', userId).not('percentage', 'is', null)
  ])
  const firstExam = exams?.[0] as { title: string; subject_id: string | null; scheduled_at: string | null; subjects: { name: string } | { name: string }[] | null } | undefined
  const subjectName = (value: { name: string } | { name: string }[] | null): string | null => Array.isArray(value) ? value[0]?.name ?? null : value?.name ?? null
  if (firstExam) return { subject_id: firstExam.subject_id, subject_name: subjectName(firstExam.subjects), topic: firstExam.title, duration_minutes: 25, reason: 'Tenés una evaluación próxima. Prepararte hoy reduce el estrés de último momento.', action: 'Prepararme' }
  const firstTask = tasks?.[0] as { title: string; subject_id: string | null; subjects: { name: string } | { name: string }[] | null } | undefined
  if (firstTask) return { subject_id: firstTask.subject_id, subject_name: subjectName(firstTask.subjects), topic: firstTask.title, duration_minutes: 20, reason: 'Tenés una tarea pendiente próxima. Un bloque corto te ayuda a empezar.', action: 'Empezar' }
  const averages = new Map<string, { total: number; count: number; name: string | null }>()
  for (const grade of (grades ?? []) as Array<{ subject_id: string | null; percentage: number; subjects: { name: string } | { name: string }[] | null }>) {
    if (!grade.subject_id) continue
    const prior = averages.get(grade.subject_id) ?? { total: 0, count: 0, name: subjectName(grade.subjects) }
    averages.set(grade.subject_id, { ...prior, total: prior.total + Number(grade.percentage), count: prior.count + 1 })
  }
  const weakest = [...averages.entries()].sort(([, a], [, b]) => (a.total / a.count) - (b.total / b.count))[0]
  if (weakest) return { subject_id: weakest[0], subject_name: weakest[1].name, topic: 'Repaso de los últimos temas', duration_minutes: 25, reason: 'Esta materia tiene tu rendimiento más bajo registrado. Un repaso dirigido puede ayudarte a mejorar.', action: 'Repasar' }
  return null
}
