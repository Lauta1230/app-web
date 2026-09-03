import { isSupabaseConfigured, supabase } from '../lib/supabase/client'
import type { Attendance, CalendarEvent, DashboardData, Exam, Note, Pet, QuizQuestion, Subject, Task } from '../types/domain'
import { AppError } from '../utils/errors'

function ready(): void { if (!isSupabaseConfigured) throw new AppError('CONFIGURATION_REQUIRED', 'Supabase is not configured') }
function check(error: { message: string } | null): void { if (error) throw new Error(error.message) }

export async function invoke<T>(name: string, body: Record<string, unknown> = {}): Promise<T> {
  ready()
  const { data, error } = await supabase.functions.invoke<{ success: boolean; data?: T; error?: { code: string; message: string } }>(name, { body })
  if (error) throw error
  if (!data?.success) throw new AppError(data?.error?.code ?? 'REQUEST_FAILED', data?.error?.message ?? 'No pudimos completar la operación.')
  return data.data as T
}

export const subjectsApi = {
  async list(): Promise<Subject[]> { ready(); const { data, error } = await supabase.from('subjects').select('id,name,color,icon,description,archived_at,created_at').is('archived_at', null).order('name'); check(error); return (data ?? []) as Subject[] },
  async create(userId: string, payload: Pick<Subject, 'name' | 'color' | 'icon' | 'description'>): Promise<Subject> { ready(); const { data, error } = await supabase.from('subjects').insert({ ...payload, user_id: userId }).select().single(); check(error); return data as Subject },
  async update(id: string, payload: Partial<Pick<Subject, 'name' | 'color' | 'icon' | 'description'>>): Promise<Subject> { ready(); const { data, error } = await supabase.from('subjects').update(payload).eq('id', id).select().single(); check(error); return data as Subject },
  async archive(id: string): Promise<void> { ready(); const { error } = await supabase.from('subjects').update({ archived_at: new Date().toISOString() }).eq('id', id); check(error) }
}

export const notesApi = {
  async list(query = ''): Promise<Note[]> { ready(); let request = supabase.from('notes').select('id,title,content,is_favorite,subject_id,updated_at,subjects(name,color)').order('updated_at', { ascending: false }); if (query.trim()) { const safeQuery = query.trim().replace(/[,.()]/g, ' '); request = request.or(`title.ilike.%${safeQuery}%,content.ilike.%${safeQuery}%`) } const { data, error } = await request; check(error); return (data ?? []) as unknown as Note[] },
  async create(userId: string, payload: Pick<Note, 'title' | 'content' | 'subject_id'>): Promise<Note> { ready(); const { data, error } = await supabase.from('notes').insert({ ...payload, user_id: userId }).select().single(); check(error); return data as Note },
  async update(id: string, payload: Partial<Pick<Note, 'title' | 'content' | 'subject_id' | 'is_favorite'>>): Promise<Note> { ready(); const { data, error } = await supabase.from('notes').update(payload).eq('id', id).select().single(); check(error); return data as Note },
  async remove(id: string): Promise<void> { ready(); const { error } = await supabase.from('notes').delete().eq('id', id); check(error) }
}

type TaskPayload = Pick<Task, 'title' | 'description' | 'priority' | 'due_at' | 'subject_id'>
export const tasksApi = {
  async list(): Promise<Task[]> { ready(); const { data, error } = await supabase.from('tasks').select('id,title,description,status,priority,due_at,subject_id,completed_at,subjects(name,color)').order('due_at', { ascending: true, nullsFirst: false }); check(error); return (data ?? []) as unknown as Task[] },
  async create(payload: TaskPayload): Promise<Task> { ready(); const { data, error } = await supabase.rpc('create_task_atomic', { p_subject_id: payload.subject_id, p_title: payload.title, p_description: payload.description, p_priority: payload.priority, p_due_at: payload.due_at }); check(error); return data as unknown as Task },
  async update(id: string, payload: Partial<TaskPayload>): Promise<Task> { ready(); const { data, error } = await supabase.from('tasks').update(payload).eq('id', id).select().single(); check(error); return data as Task },
  async remove(id: string): Promise<void> { ready(); const { error } = await supabase.from('tasks').delete().eq('id', id); check(error) },
  async complete(id: string): Promise<{ xp: number }> { const data = await invoke<{ task_id: string; xp_awarded: number }>('complete-task', { task_id: id }); return { xp: data.xp_awarded } }
}

export const eventsApi = {
  async list(start?: string, end?: string): Promise<CalendarEvent[]> { ready(); let request = supabase.from('calendar_events').select('id,title,event_type,starts_at,duration_minutes,reminder_minutes,subject_id,notes,subjects(name,color)').order('starts_at'); if (start) request = request.gte('starts_at', start); if (end) request = request.lte('starts_at', end); const { data, error } = await request; check(error); return (data ?? []) as unknown as CalendarEvent[] },
  async create(userId: string, payload: Omit<CalendarEvent, 'id' | 'subjects'>): Promise<CalendarEvent> { ready(); const { data, error } = await supabase.from('calendar_events').insert({ ...payload, user_id: userId }).select().single(); check(error); return data as CalendarEvent },
  async remove(id: string): Promise<void> { ready(); const { error } = await supabase.from('calendar_events').delete().eq('id', id); check(error) }
}

type ExamPayload = Omit<Exam, 'id' | 'percentage' | 'status' | 'subjects'>
async function saveExam(payload: ExamPayload & { exam_id?: string }): Promise<Exam> {
  const result = await invoke<{ exam: Exam }>('process-exam', { action: 'save', ...payload })
  return result.exam
}
export const examsApi = {
  async list(): Promise<Exam[]> { ready(); const { data, error } = await supabase.from('exams').select('id,title,subject_id,scheduled_at,grade,max_grade,passing_percentage,percentage,status,notes,subjects(name,color)').order('scheduled_at', { ascending: true, nullsFirst: false }); check(error); return (data ?? []) as unknown as Exam[] },
  async create(payload: ExamPayload): Promise<Exam> { return saveExam(payload) },
  async update(id: string, payload: ExamPayload): Promise<Exam> { return saveExam({ ...payload, exam_id: id }) },
  async remove(id: string): Promise<void> { ready(); const { error } = await supabase.from('exams').delete().eq('id', id); check(error) }
}

export const attendanceApi = {
  async list(): Promise<Attendance[]> { ready(); const { data, error } = await supabase.from('attendance_records').select('id,subject_id,attendance_date,morning_status,afternoon_status,notes,subjects(name)').order('attendance_date', { ascending: false }); check(error); return (data ?? []) as unknown as Attendance[] },
  async save(userId: string, payload: Omit<Attendance, 'id' | 'subjects'>): Promise<Attendance> { ready(); const { data, error } = await supabase.from('attendance_records').upsert({ ...payload, user_id: userId }, { onConflict: 'user_id,subject_id,attendance_date' }).select().single(); check(error); return data as Attendance }
}

export const petsApi = {
  async get(): Promise<Pet | null> { ready(); const { data, error } = await supabase.from('pets').select('id,name,species,level,happiness,energy').maybeSingle(); check(error); return data as Pet | null }
}

export const appApi = {
  dashboard: (): Promise<DashboardData> => invoke<DashboardData>('dashboard'),
  recommend: () => invoke<{ recommendation: DashboardData['recommendation'] }>('study-recommendation'),
  petCare: (action: 'feed' | 'play' | 'rest') => invoke<{ pet: Pet; reaction: string }>('pet-care', { action }),
  aiChat: (body: { message: string; conversation_id?: string; subject_id?: string; note_id?: string; document_id?: string; mode?: string }) => invoke<{ conversation_id: string; message: string }>('ai-chat', body),
  humanize: (text: string, style: string) => invoke<{ text: string }>('humanize-text', { text, style }),
  analyzeText: (text: string) => invoke<{ summary: string; signals: Array<{ label: string; detail: string; level: string }>; suggestions: string[]; disclaimer: string }>('analyze-ai-text', { text }),
  createQuiz: (body: { subject_id: string; topic: string; difficulty: string; question_count: number; source_text?: string }) => invoke<{ quiz_id: string; title: string; difficulty: string; questions: QuizQuestion[] }>('ai-quiz', body),
  submitQuiz: (quizId: string, answers: Array<{ question_id: string; answer: string }>) => invoke<{ score: number; correct_answers: number; question_count: number; xp_awarded: number; answers: Array<{ question_id: string; is_correct: boolean; feedback: string }> }>('submit-quiz', { quiz_id: quizId, answers }),
  completeStudySession: (body: { started_at: string; duration_seconds: number; mode: string; subject_id?: string | null }) => invoke<{ session_id: string; xp_awarded: number }>('complete-study-session', body)
}
