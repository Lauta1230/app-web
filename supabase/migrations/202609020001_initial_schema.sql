-- Companion Study: production schema. Apply with `supabase db push`.
create extension if not exists pgcrypto;

create type public.education_level as enum ('secondary', 'university', 'tertiary', 'other');
create type public.ai_personality as enum ('teacher', 'companion', 'teen', 'simple');
create type public.task_status as enum ('pending', 'completed', 'cancelled');
create type public.task_priority as enum ('low', 'medium', 'high', 'urgent');
create type public.event_type as enum ('task', 'exam', 'class', 'study', 'reminder', 'other');
create type public.exam_status as enum ('pending', 'passed', 'failed');
create type public.attendance_status as enum ('present', 'absent', 'justified', 'not_recorded');
create type public.study_mode as enum ('free_study', 'ai_tutor', 'quiz', 'flashcards', 'voice', 'review');
create type public.document_status as enum ('pending', 'processing', 'completed', 'failed');
create type public.document_type as enum ('note', 'exam', 'task', 'document');
create type public.quiz_status as enum ('draft', 'active', 'completed', 'cancelled');
create type public.question_type as enum ('multiple_choice', 'true_false', 'short_answer', 'open_answer', 'oral');
create type public.quiz_difficulty as enum ('easy', 'normal', 'hard');
create type public.xp_source as enum ('task_completed', 'quiz_completed', 'study_session_completed', 'exam_recorded', 'achievement_unlocked', 'daily_goal_completed');
create type public.pet_species as enum ('cat', 'dog', 'fox', 'owl');
create type public.pet_care_action as enum ('feed', 'play', 'rest');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  education_level public.education_level,
  timezone text not null default 'UTC' check (char_length(timezone) between 1 and 64),
  ai_personality public.ai_personality not null default 'companion',
  onboarding_completed boolean not null default false,
  avatar_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.subjects (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 80), color text not null default '#7c6cff' check (color ~ '^#[0-9A-Fa-f]{6}$'),
  icon text not null default 'book-open' check (char_length(icon) <= 40), description text, archived_at timestamptz,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(user_id, name)
);

create table public.notes (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, title text not null check (char_length(trim(title)) between 1 and 160),
  content text not null default '', is_favorite boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.documents (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, name text not null check (char_length(trim(name)) between 1 and 255),
  storage_path text not null unique, mime_type text not null, size_bytes integer not null check (size_bytes > 0 and size_bytes <= 10485760),
  document_type public.document_type not null default 'document', processing_status public.document_status not null default 'pending',
  extracted_text text, extracted_data jsonb, error_message text, confirmed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, title text not null check (char_length(trim(title)) between 1 and 180), description text,
  status public.task_status not null default 'pending', priority public.task_priority not null default 'medium', due_at timestamptz,
  completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint valid_task_completion check ((status = 'completed' and completed_at is not null) or (status <> 'completed'))
);

create table public.calendar_events (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, task_id uuid unique references public.tasks(id) on delete set null,
  title text not null check (char_length(trim(title)) between 1 and 180), event_type public.event_type not null default 'other', starts_at timestamptz not null,
  duration_minutes integer not null default 60 check (duration_minutes between 5 and 1440), reminder_minutes integer check (reminder_minutes between 0 and 43200),
  notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table public.exams (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, title text not null check (char_length(trim(title)) between 1 and 180),
  scheduled_at timestamptz, grade numeric(6,2) check (grade >= 0), max_grade numeric(6,2) check (max_grade > 0),
  passing_percentage numeric(5,2) not null default 60 check (passing_percentage between 0 and 100), percentage numeric(5,2), status public.exam_status not null default 'pending',
  notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint valid_exam_grade check ((grade is null and max_grade is null and percentage is null) or (grade is not null and max_grade is not null and percentage between 0 and 100))
);

create table public.attendance_records (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, attendance_date date not null,
  morning_status public.attendance_status not null default 'not_recorded', afternoon_status public.attendance_status not null default 'not_recorded',
  notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(), unique(user_id, subject_id, attendance_date)
);

create table public.study_sessions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, started_at timestamptz not null default now(), ended_at timestamptz,
  duration_seconds integer not null default 0 check (duration_seconds >= 0 and duration_seconds <= 86400), mode public.study_mode not null default 'free_study',
  completed boolean not null default false, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint valid_completed_session check (not completed or ended_at is not null)
);

create table public.ai_conversations (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, note_id uuid references public.notes(id) on delete set null,
  mode public.study_mode not null default 'ai_tutor', title text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.ai_messages (
  id uuid primary key default gen_random_uuid(), conversation_id uuid not null references public.ai_conversations(id) on delete cascade,
  role text not null check (role in ('user', 'assistant', 'system')), content text not null check (char_length(content) <= 30000),
  created_at timestamptz not null default now()
);

create table public.quizzes (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid references public.subjects(id) on delete set null, title text not null check (char_length(trim(title)) between 1 and 180), topic text,
  difficulty public.quiz_difficulty not null default 'normal', status public.quiz_status not null default 'draft', score numeric(5,2) check (score between 0 and 100),
  started_at timestamptz, completed_at timestamptz, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.quiz_questions (
  id uuid primary key default gen_random_uuid(), quiz_id uuid not null references public.quizzes(id) on delete cascade,
  position smallint not null check (position between 1 and 20), question_type public.question_type not null, prompt text not null,
  options jsonb, created_at timestamptz not null default now(), unique(quiz_id, position),
  constraint options_array check (options is null or jsonb_typeof(options) = 'array')
);
-- Answer keys are server-only. There is deliberately no browser RLS policy.
create table public.quiz_answer_keys (
  question_id uuid primary key references public.quiz_questions(id) on delete cascade, accepted_answers jsonb not null check (jsonb_typeof(accepted_answers) = 'array'), explanation text, created_at timestamptz not null default now()
);
create table public.quiz_answers (
  id uuid primary key default gen_random_uuid(), quiz_id uuid not null references public.quizzes(id) on delete cascade,
  question_id uuid not null references public.quiz_questions(id) on delete cascade, answer text not null check (char_length(answer) <= 5000),
  is_correct boolean, feedback text, created_at timestamptz not null default now(), unique(quiz_id, question_id)
);

create table public.levels (id smallint primary key, name text not null unique, min_xp integer not null unique check (min_xp >= 0));
insert into public.levels (id, name, min_xp) values (1, 'Principiante', 0), (2, 'Aprendiz', 500), (3, 'Estudiante', 1200), (4, 'Aplicado', 2500), (5, 'Experto', 5000), (6, 'Maestro', 10000);

create table public.xp_transactions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade,
  source public.xp_source not null, source_id uuid not null, amount integer not null check (amount > 0 and amount <= 1000), description text,
  created_at timestamptz not null default now(), unique(user_id, source, source_id)
);
create table public.streaks (
  user_id uuid primary key references public.profiles(id) on delete cascade, current_streak integer not null default 0 check (current_streak >= 0),
  longest_streak integer not null default 0 check (longest_streak >= 0), last_activity_date date, updated_at timestamptz not null default now()
);
create table public.pets (
  id uuid primary key default gen_random_uuid(), user_id uuid not null unique references public.profiles(id) on delete cascade,
  species public.pet_species not null default 'cat', name text not null check (char_length(trim(name)) between 1 and 32), level smallint not null default 1 check (level between 1 and 100),
  happiness smallint not null default 70 check (happiness between 0 and 100), energy smallint not null default 70 check (energy between 0 and 100),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.pet_items (id uuid primary key default gen_random_uuid(), name text not null unique, item_type text not null, effect jsonb not null default '{}'::jsonb, created_at timestamptz not null default now());
create table public.user_pet_items (user_id uuid not null references public.profiles(id) on delete cascade, item_id uuid not null references public.pet_items(id) on delete cascade, quantity integer not null default 0 check (quantity >= 0), primary key(user_id, item_id));
create table public.achievements (id uuid primary key default gen_random_uuid(), code text not null unique, title text not null, description text not null, xp_reward integer not null default 0 check (xp_reward between 0 and 1000), created_at timestamptz not null default now());
create table public.user_achievements (user_id uuid not null references public.profiles(id) on delete cascade, achievement_id uuid not null references public.achievements(id) on delete cascade, unlocked_at timestamptz not null default now(), primary key(user_id, achievement_id));
insert into public.achievements (code, title, description, xp_reward) values
 ('first_study', 'Primer estudio', 'Completaste tu primera sesión de estudio.', 15),
 ('first_task', 'Primera tarea', 'Completaste tu primera tarea.', 15),
 ('first_exam', 'Primera evaluación', 'Registraste tu primera evaluación.', 15),
 ('streak_7', 'Una semana constante', 'Alcanzaste una racha de 7 días.', 30),
 ('questions_100', 'Cien preguntas', 'Respondé 100 preguntas de quiz.', 50),
 ('exams_10', 'Diez evaluaciones', 'Registraste 10 evaluaciones.', 50)
on conflict (code) do nothing;
create table public.notifications (id uuid primary key default gen_random_uuid(), user_id uuid not null references public.profiles(id) on delete cascade, title text not null, body text not null, read_at timestamptz, created_at timestamptz not null default now());

create index subjects_active_idx on public.subjects(user_id) where archived_at is null;
create index notes_user_subject_idx on public.notes(user_id, subject_id, updated_at desc);
create index tasks_due_idx on public.tasks(user_id, status, due_at);
create index events_start_idx on public.calendar_events(user_id, starts_at);
create index exams_schedule_idx on public.exams(user_id, scheduled_at);
create index sessions_user_started_idx on public.study_sessions(user_id, started_at desc);
create index conversations_user_updated_idx on public.ai_conversations(user_id, updated_at desc);
create index messages_conversation_created_idx on public.ai_messages(conversation_id, created_at);
create index quiz_questions_quiz_idx on public.quiz_questions(quiz_id, position);
create index xp_user_created_idx on public.xp_transactions(user_id, created_at desc);
create index notifications_user_idx on public.notifications(user_id, created_at desc);

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;
create trigger profiles_updated before update on public.profiles for each row execute function public.touch_updated_at();
create trigger subjects_updated before update on public.subjects for each row execute function public.touch_updated_at();
create trigger notes_updated before update on public.notes for each row execute function public.touch_updated_at();
create trigger documents_updated before update on public.documents for each row execute function public.touch_updated_at();
create trigger tasks_updated before update on public.tasks for each row execute function public.touch_updated_at();
create trigger calendar_events_updated before update on public.calendar_events for each row execute function public.touch_updated_at();
create trigger exams_updated before update on public.exams for each row execute function public.touch_updated_at();
create trigger attendance_updated before update on public.attendance_records for each row execute function public.touch_updated_at();
create trigger study_sessions_updated before update on public.study_sessions for each row execute function public.touch_updated_at();
create trigger conversations_updated before update on public.ai_conversations for each row execute function public.touch_updated_at();
create trigger quizzes_updated before update on public.quizzes for each row execute function public.touch_updated_at();
create trigger pets_updated before update on public.pets for each row execute function public.touch_updated_at();

create or replace function public.create_profile_for_user() returns trigger language plpgsql security definer set search_path = public as $$
begin insert into public.profiles (id, display_name) values (new.id, coalesce(new.raw_user_meta_data->>'display_name', '')); insert into public.streaks(user_id) values (new.id); return new; end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.create_profile_for_user();

-- Grades and status cannot be forged inconsistently by a client.
create or replace function public.calculate_exam_values() returns trigger language plpgsql as $$
begin if new.grade is not null and new.max_grade is not null then new.percentage = round((new.grade / new.max_grade) * 100, 2); new.status = case when new.percentage >= new.passing_percentage then 'passed'::public.exam_status else 'failed'::public.exam_status end; else new.percentage = null; new.status = 'pending'::public.exam_status; end if; return new; end; $$;
create trigger exam_values before insert or update on public.exams for each row execute function public.calculate_exam_values();

-- Called by service-only Edge Functions. The unique constraint makes retries idempotent.
create or replace function public.award_xp_internal(p_user_id uuid, p_source public.xp_source, p_source_id uuid, p_amount integer, p_description text default null)
returns table(awarded boolean, total_xp integer, current_streak integer) language plpgsql security definer set search_path = public as $$
declare inserted_count integer; activity_day date := (now() at time zone coalesce((select timezone from public.profiles where id=p_user_id), 'UTC'))::date; s public.streaks%rowtype;
begin
  if p_amount < 1 or p_amount > 1000 then raise exception 'invalid XP amount'; end if;
  insert into public.xp_transactions(user_id, source, source_id, amount, description) values(p_user_id,p_source,p_source_id,p_amount,p_description) on conflict (user_id,source,source_id) do nothing;
  get diagnostics inserted_count = row_count;
  select coalesce(sum(amount),0)::integer into total_xp from public.xp_transactions where user_id=p_user_id;
  select * into s from public.streaks where user_id=p_user_id for update;
  if inserted_count = 1 then
    if s.last_activity_date is null then s.current_streak := 1;
    elsif s.last_activity_date = activity_day then null;
    elsif s.last_activity_date = activity_day - 1 then s.current_streak := s.current_streak + 1;
    else s.current_streak := 1; end if;
    s.longest_streak := greatest(s.longest_streak, s.current_streak); s.last_activity_date := activity_day;
    update public.streaks set current_streak=s.current_streak, longest_streak=s.longest_streak, last_activity_date=s.last_activity_date, updated_at=now() where user_id=p_user_id;
    update public.pets set happiness=least(100,happiness+3), energy=least(100,energy+1) where user_id=p_user_id;
  end if;
  awarded := inserted_count = 1; current_streak := s.current_streak; return next;
end; $$;

-- RLS: private data is scoped to the authenticated owner, including relation-owned rows.
alter table public.profiles enable row level security;
alter table public.subjects enable row level security; alter table public.notes enable row level security; alter table public.documents enable row level security; alter table public.tasks enable row level security; alter table public.calendar_events enable row level security; alter table public.exams enable row level security; alter table public.attendance_records enable row level security; alter table public.study_sessions enable row level security; alter table public.ai_conversations enable row level security; alter table public.ai_messages enable row level security; alter table public.quizzes enable row level security; alter table public.quiz_questions enable row level security; alter table public.quiz_answer_keys enable row level security; alter table public.quiz_answers enable row level security; alter table public.levels enable row level security; alter table public.xp_transactions enable row level security; alter table public.streaks enable row level security; alter table public.pets enable row level security; alter table public.pet_items enable row level security; alter table public.user_pet_items enable row level security; alter table public.achievements enable row level security; alter table public.user_achievements enable row level security; alter table public.notifications enable row level security;

create policy "profile owner" on public.profiles for all using (auth.uid() = id) with check (auth.uid() = id);
create policy "subject owner" on public.subjects for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "note owner" on public.notes for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "document owner" on public.documents for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "task owner" on public.tasks for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "calendar owner" on public.calendar_events for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "exam owner" on public.exams for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "attendance owner" on public.attendance_records for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "session owner" on public.study_sessions for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "conversation owner" on public.ai_conversations for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "message conversation owner" on public.ai_messages for select using (exists(select 1 from public.ai_conversations c where c.id=conversation_id and c.user_id=auth.uid()));
create policy "quiz owner" on public.quizzes for select using (auth.uid() = user_id);
create policy "question quiz owner" on public.quiz_questions for select using (exists(select 1 from public.quizzes q where q.id=quiz_id and q.user_id=auth.uid()));
create policy "answer quiz owner" on public.quiz_answers for select using (exists(select 1 from public.quizzes q where q.id=quiz_id and q.user_id=auth.uid()));
create policy "levels readable" on public.levels for select using (true);
create policy "xp readable own" on public.xp_transactions for select using (auth.uid() = user_id);
create policy "streak readable own" on public.streaks for select using (auth.uid() = user_id);
create policy "pet owner" on public.pets for select using (auth.uid() = user_id);
create policy "items readable" on public.pet_items for select using (true);
create policy "user items own" on public.user_pet_items for select using (auth.uid() = user_id);
create policy "achievements readable" on public.achievements for select using (true);
create policy "user achievements own" on public.user_achievements for select using (auth.uid() = user_id);
create policy "notifications own" on public.notifications for select using (auth.uid() = user_id);
create policy "notification read own" on public.notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Storage is private. Upload paths must start with the caller's UUID.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
 ('documents','documents',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp','text/plain']),
 ('avatars','avatars',false,2097152,array['image/jpeg','image/png','image/webp']),
 ('audio','audio',false,5242880,array['audio/webm','audio/ogg','audio/mpeg'])
on conflict (id) do nothing;
create policy "private files select own folder" on storage.objects for select to authenticated using (bucket_id in ('documents','avatars','audio') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "private files insert own folder" on storage.objects for insert to authenticated with check (bucket_id in ('documents','avatars','audio') and (storage.foldername(name))[1] = auth.uid()::text);
create policy "private files update own folder" on storage.objects for update to authenticated
using (
  bucket_id in ('documents', 'avatars', 'audio')
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id in ('documents', 'avatars', 'audio')
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "private files delete own folder" on storage.objects for delete to authenticated using (bucket_id in ('documents','avatars','audio') and (storage.foldername(name))[1] = auth.uid()::text);

grant execute on function public.award_xp_internal(uuid, public.xp_source, uuid, integer, text) to service_role;
revoke all on function public.award_xp_internal(uuid, public.xp_source, uuid, integer, text) from public, anon, authenticated;
