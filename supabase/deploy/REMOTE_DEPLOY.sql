-- Companion Study — manual first deployment for a verified empty Supabase project.
--
-- Target project reference (verify in the Supabase Dashboard before running):
-- jqogsofwodvgfqvbpcza
--
-- Purpose: execute the complete schema plus P0/P1 hardening in Supabase SQL Editor.
-- This file is a self-contained, ordered rendering of:
--   1. 202609020001_initial_schema.sql
--   2. 202609020002_security_integrity.sql
--
-- Safety characteristics:
-- - Intended for ONE execution only, on a project with no Companion Study schema.
-- - Uses a single transaction: an error rolls back the whole deployment.
-- - Contains no DROP TABLE, TRUNCATE, DELETE, credentials, API keys, access tokens,
--   database passwords, service-role keys, or Gemini configuration.
-- - It creates only schema objects and the fixed application catalog rows required by
--   the product (levels and achievements); it creates no academic or user production data.
-- - The P0/P1 section refuses to continue if legacy unsafe references or logical
--   attendance duplicates are detected. It never deletes or merges existing rows.
--
-- Do not run this against an already-deployed project. Inspect its migration/schema
-- state first and use an additive reviewed migration path instead.

begin;

-- ============================================================================
-- SECTION 1 — FOUNDATION: extensions, enums, tables, indexes, triggers,
--             baseline RLS, Storage buckets/policies, and initial internal XP RPC.
-- ============================================================================

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
create policy "private files update own folder" on storage.objects for update to authenticated using (bucket_id in ('documents','avatars','audio') and (storage.foldername(name))[1] = auth.uid()::text) with check ((storage.foldername(name))[1] = auth.uid()::text);
create policy "private files delete own folder" on storage.objects for delete to authenticated using (bucket_id in ('documents','avatars','audio') and (storage.foldername(name))[1] = auth.uid()::text);

grant execute on function public.award_xp_internal(uuid, public.xp_source, uuid, integer, text) to service_role;
revoke all on function public.award_xp_internal(uuid, public.xp_source, uuid, integer, text) from public, anon, authenticated;

-- ============================================================================
-- SECTION 2 — P0/P1 HARDENING: tenant ownership, document path integrity,
--             NULL-safe attendance uniqueness, restricted browser privileges,
--             server-side XP and atomic mutation RPCs.
-- ============================================================================

-- Security and integrity hardening. This migration is additive/non-destructive:
-- it validates all NEW writes, preserves existing rows, and aborts before replacing
-- the attendance constraint if legacy logical duplicates are found.

-- A document metadata row must never point service-role OCR at another user's object.
-- Existing unsafe relationships are reported before adding constraints/triggers; no data
-- is deleted or silently repaired by this migration.
do $$
begin
  if exists (select 1 from public.documents where storage_path not like (user_id::text || '/%')) then
    raise exception 'Cannot install document path integrity: rows with a foreign storage path must be reviewed manually first';
  end if;
  if exists (select 1 from public.notes child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.documents child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.tasks child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.calendar_events child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.calendar_events child join public.tasks task on task.id = child.task_id where task.user_id <> child.user_id)
     or exists (select 1 from public.exams child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.attendance_records child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.study_sessions child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.ai_conversations child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.ai_conversations child join public.notes note on note.id = child.note_id where note.user_id <> child.user_id)
     or exists (select 1 from public.quizzes child join public.subjects subject on subject.id = child.subject_id where subject.user_id <> child.user_id)
     or exists (select 1 from public.quiz_answers answer join public.quiz_questions question on question.id = answer.question_id where question.quiz_id <> answer.quiz_id) then
    raise exception 'Cannot install tenant integrity: cross-owner references must be reviewed manually first';
  end if;
end;
$$;
alter table public.documents
  add constraint documents_storage_path_matches_owner
  check (storage_path like (user_id::text || '/%'));

-- Enforce tenant ownership of every optional subject relation at database level.
create or replace function public.enforce_subject_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.subject_id is not null
     and not exists (
       select 1 from public.subjects subject
       where subject.id = new.subject_id and subject.user_id = new.user_id
     ) then
    raise exception using errcode = '23514', message = 'Referenced subject must belong to the same user';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_calendar_task_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.task_id is not null
     and not exists (
       select 1 from public.tasks task
       where task.id = new.task_id and task.user_id = new.user_id
     ) then
    raise exception using errcode = '23514', message = 'Referenced task must belong to the same user';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_conversation_note_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.note_id is not null
     and not exists (
       select 1 from public.notes note
       where note.id = new.note_id and note.user_id = new.user_id
     ) then
    raise exception using errcode = '23514', message = 'Referenced note must belong to the same user';
  end if;
  return new;
end;
$$;

create or replace function public.enforce_quiz_answer_question_owner()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.quiz_questions question
    where question.id = new.question_id and question.quiz_id = new.quiz_id
  ) then
    raise exception using errcode = '23514', message = 'Quiz answer question must belong to the same quiz';
  end if;
  return new;
end;
$$;

drop trigger if exists notes_subject_owner on public.notes;
create trigger notes_subject_owner before insert or update of user_id, subject_id on public.notes
for each row execute function public.enforce_subject_owner();
drop trigger if exists documents_subject_owner on public.documents;
create trigger documents_subject_owner before insert or update of user_id, subject_id on public.documents
for each row execute function public.enforce_subject_owner();
drop trigger if exists tasks_subject_owner on public.tasks;
create trigger tasks_subject_owner before insert or update of user_id, subject_id on public.tasks
for each row execute function public.enforce_subject_owner();
drop trigger if exists calendar_events_subject_owner on public.calendar_events;
create trigger calendar_events_subject_owner before insert or update of user_id, subject_id on public.calendar_events
for each row execute function public.enforce_subject_owner();
drop trigger if exists exams_subject_owner on public.exams;
create trigger exams_subject_owner before insert or update of user_id, subject_id on public.exams
for each row execute function public.enforce_subject_owner();
drop trigger if exists attendance_subject_owner on public.attendance_records;
create trigger attendance_subject_owner before insert or update of user_id, subject_id on public.attendance_records
for each row execute function public.enforce_subject_owner();
drop trigger if exists study_sessions_subject_owner on public.study_sessions;
create trigger study_sessions_subject_owner before insert or update of user_id, subject_id on public.study_sessions
for each row execute function public.enforce_subject_owner();
drop trigger if exists conversations_subject_owner on public.ai_conversations;
create trigger conversations_subject_owner before insert or update of user_id, subject_id on public.ai_conversations
for each row execute function public.enforce_subject_owner();
drop trigger if exists quizzes_subject_owner on public.quizzes;
create trigger quizzes_subject_owner before insert or update of user_id, subject_id on public.quizzes
for each row execute function public.enforce_subject_owner();
drop trigger if exists calendar_events_task_owner on public.calendar_events;
create trigger calendar_events_task_owner before insert or update of user_id, task_id on public.calendar_events
for each row execute function public.enforce_calendar_task_owner();
drop trigger if exists conversations_note_owner on public.ai_conversations;
create trigger conversations_note_owner before insert or update of user_id, note_id on public.ai_conversations
for each row execute function public.enforce_conversation_note_owner();
drop trigger if exists quiz_answers_question_owner on public.quiz_answers;
create trigger quiz_answers_question_owner before insert or update of quiz_id, question_id on public.quiz_answers
for each row execute function public.enforce_quiz_answer_question_owner();

-- PostgreSQL treats NULL as distinct in ordinary UNIQUE constraints. Abort safely if
-- existing data would violate the stronger business rule; no row is deleted or merged.
do $$
begin
  if exists (
    select 1
    from public.attendance_records
    group by user_id, subject_id, attendance_date
    having count(*) > 1
  ) then
    raise exception 'Cannot install attendance logical uniqueness: duplicate rows must be reviewed manually first';
  end if;
end;
$$;
alter table public.attendance_records
  drop constraint if exists attendance_records_user_id_subject_id_attendance_date_key;
alter table public.attendance_records
  add constraint attendance_records_logical_unique unique nulls not distinct (user_id, subject_id, attendance_date);

-- Browser CRUD can create/edit a task, but cannot self-mark completion or manufacture
-- completed study/exam events. Those state transitions are server-side below.
revoke insert, update on public.tasks from anon, authenticated;
grant insert (user_id, subject_id, title, description, priority, due_at) on public.tasks to authenticated;
grant update (subject_id, title, description, priority, due_at) on public.tasks to authenticated;
revoke insert, update on public.study_sessions from anon, authenticated;
revoke insert, update on public.exams from anon, authenticated;
revoke update on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

-- XP reward limits are server-side circuit breakers against synthetic activity farming.
-- They are intentionally modest and reset in the user's stored timezone.
create or replace function public.award_xp_internal(
  p_user_id uuid,
  p_source public.xp_source,
  p_source_id uuid,
  p_amount integer,
  p_description text default null
)
returns table(awarded boolean, total_xp integer, current_streak integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  inserted_count integer;
  activity_day date := (now() at time zone coalesce((select timezone from public.profiles where id = p_user_id), 'UTC'))::date;
  day_start timestamptz;
  daily_limit integer;
  daily_awards integer;
  streak public.streaks%rowtype;
begin
  if p_amount < 1 or p_amount > 1000 then
    raise exception 'Invalid XP amount';
  end if;

  select * into streak from public.streaks where user_id = p_user_id for update;
  if not found then
    raise exception 'Streak profile is missing';
  end if;

  -- Preserve idempotency before applying rate limits.
  if exists (
    select 1 from public.xp_transactions
    where user_id = p_user_id and source = p_source and source_id = p_source_id
  ) then
    select coalesce(sum(amount), 0)::integer into total_xp from public.xp_transactions where user_id = p_user_id;
    awarded := false;
    current_streak := streak.current_streak;
    return next;
    return;
  end if;

  daily_limit := case p_source
    when 'task_completed' then 5
    when 'study_session_completed' then 4
    when 'quiz_completed' then 5
    when 'exam_recorded' then 3
    when 'daily_goal_completed' then 1
    else null
  end;
  if daily_limit is not null then
    day_start := (activity_day::timestamp at time zone coalesce((select timezone from public.profiles where id = p_user_id), 'UTC'));
    select count(*) into daily_awards
    from public.xp_transactions
    where user_id = p_user_id
      and source = p_source
      and created_at >= day_start
      and created_at < day_start + interval '1 day';
    if daily_awards >= daily_limit then
      select coalesce(sum(amount), 0)::integer into total_xp from public.xp_transactions where user_id = p_user_id;
      awarded := false;
      current_streak := streak.current_streak;
      return next;
      return;
    end if;
  end if;

  insert into public.xp_transactions(user_id, source, source_id, amount, description)
  values(p_user_id, p_source, p_source_id, p_amount, p_description);
  get diagnostics inserted_count = row_count;
  select coalesce(sum(amount), 0)::integer into total_xp from public.xp_transactions where user_id = p_user_id;

  if inserted_count = 1 then
    if streak.last_activity_date is null then
      streak.current_streak := 1;
    elsif streak.last_activity_date = activity_day then
      null;
    elsif streak.last_activity_date = activity_day - 1 then
      streak.current_streak := streak.current_streak + 1;
    else
      streak.current_streak := 1;
    end if;
    streak.longest_streak := greatest(streak.longest_streak, streak.current_streak);
    streak.last_activity_date := activity_day;
    update public.streaks
    set current_streak = streak.current_streak,
        longest_streak = streak.longest_streak,
        last_activity_date = streak.last_activity_date,
        updated_at = now()
    where user_id = p_user_id;
    update public.pets
    set happiness = least(100, happiness + 3), energy = least(100, energy + 1)
    where user_id = p_user_id;
  end if;

  awarded := inserted_count = 1;
  current_streak := streak.current_streak;
  return next;
end;
$$;

create or replace function public.check_achievements_internal(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  achievement public.achievements%rowtype;
  inserted_count integer;
  unlocked jsonb := '[]'::jsonb;
  should_unlock boolean;
begin
  for achievement in select * from public.achievements order by code loop
    should_unlock := case achievement.code
      when 'first_task' then exists (select 1 from public.tasks where user_id = p_user_id and status = 'completed')
      when 'first_study' then exists (select 1 from public.study_sessions where user_id = p_user_id and completed and duration_seconds >= 60)
      when 'first_exam' then exists (select 1 from public.exams where user_id = p_user_id and grade is not null and max_grade is not null)
      when 'streak_7' then coalesce((select current_streak >= 7 from public.streaks where user_id = p_user_id), false)
      when 'questions_100' then (select count(*) from public.quiz_answers answer join public.quizzes quiz on quiz.id = answer.quiz_id where quiz.user_id = p_user_id) >= 100
      when 'exams_10' then (select count(*) from public.exams where user_id = p_user_id and grade is not null) >= 10
      else false
    end;
    if should_unlock then
      insert into public.user_achievements(user_id, achievement_id)
      values(p_user_id, achievement.id)
      on conflict (user_id, achievement_id) do nothing;
      get diagnostics inserted_count = row_count;
      if inserted_count = 1 then
        perform public.award_xp_internal(p_user_id, 'achievement_unlocked', achievement.id, achievement.xp_reward, 'Logro: ' || achievement.title);
        unlocked := unlocked || jsonb_build_array(jsonb_build_object('code', achievement.code, 'title', achievement.title, 'xp_reward', achievement.xp_reward));
      end if;
    end if;
  end loop;
  return unlocked;
end;
$$;

create or replace function public.complete_task_atomic(p_user_id uuid, p_task_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  task public.tasks%rowtype;
  award record;
  achievements jsonb;
begin
  select * into task from public.tasks where id = p_task_id and user_id = p_user_id for update;
  if not found then raise exception 'TASK_NOT_FOUND'; end if;
  if task.status = 'cancelled' then raise exception 'TASK_CANCELLED'; end if;
  if task.status = 'pending' then
    update public.tasks set status = 'completed', completed_at = now() where id = task.id returning * into task;
  end if;
  select * into award from public.award_xp_internal(p_user_id, 'task_completed', task.id, 30, 'Tarea completada: ' || task.title);
  achievements := public.check_achievements_internal(p_user_id);
  return jsonb_build_object('task_id', task.id, 'xp_awarded', case when award.awarded then 30 else 0 end, 'current_streak', award.current_streak, 'achievements', achievements);
end;
$$;

create or replace function public.complete_study_session_atomic(
  p_user_id uuid,
  p_subject_id uuid,
  p_started_at timestamptz,
  p_duration_seconds integer,
  p_mode public.study_mode
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  session_id uuid;
  award record;
  achievements jsonb;
begin
  if p_duration_seconds < 60 or p_duration_seconds > 86400 then raise exception 'INVALID_SESSION_DURATION'; end if;
  if p_started_at > now() or p_started_at + make_interval(secs => p_duration_seconds) > now() + interval '2 minutes' then raise exception 'INVALID_SESSION_TIME'; end if;
  insert into public.study_sessions(user_id, subject_id, started_at, ended_at, duration_seconds, mode, completed)
  values(p_user_id, p_subject_id, p_started_at, now(), p_duration_seconds, p_mode, true)
  returning id into session_id;
  select * into award from public.award_xp_internal(p_user_id, 'study_session_completed', session_id, 25, 'Sesión de estudio completada');
  achievements := public.check_achievements_internal(p_user_id);
  return jsonb_build_object('session_id', session_id, 'xp_awarded', case when award.awarded then 25 else 0 end, 'current_streak', award.current_streak, 'achievements', achievements);
end;
$$;

create or replace function public.save_exam_atomic(
  p_user_id uuid,
  p_exam_id uuid,
  p_title text,
  p_subject_id uuid,
  p_scheduled_at timestamptz,
  p_grade numeric,
  p_max_grade numeric,
  p_passing_percentage numeric,
  p_notes text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  exam public.exams%rowtype;
  award record;
  achievements jsonb := '[]'::jsonb;
begin
  if char_length(trim(coalesce(p_title, ''))) not between 1 and 180 then raise exception 'INVALID_EXAM_TITLE'; end if;
  if p_grade is not null and (p_max_grade is null or p_max_grade <= 0 or p_grade < 0) then raise exception 'INVALID_EXAM_GRADE'; end if;
  if p_grade is null then p_max_grade := null; end if;
  if p_passing_percentage is null or p_passing_percentage < 0 or p_passing_percentage > 100 then raise exception 'INVALID_PASSING_PERCENTAGE'; end if;

  if p_exam_id is null then
    insert into public.exams(user_id, subject_id, title, scheduled_at, grade, max_grade, passing_percentage, notes)
    values(p_user_id, p_subject_id, trim(p_title), p_scheduled_at, p_grade, p_max_grade, p_passing_percentage, p_notes)
    returning * into exam;
  else
    select * into exam from public.exams where id = p_exam_id and user_id = p_user_id for update;
    if not found then raise exception 'EXAM_NOT_FOUND'; end if;
    update public.exams
    set subject_id = p_subject_id, title = trim(p_title), scheduled_at = p_scheduled_at, grade = p_grade,
        max_grade = p_max_grade, passing_percentage = p_passing_percentage, notes = p_notes
    where id = p_exam_id
    returning * into exam;
  end if;

  if exam.grade is not null and exam.max_grade is not null then
    select * into award from public.award_xp_internal(p_user_id, 'exam_recorded', exam.id, 20, 'Evaluación registrada: ' || exam.title);
    achievements := public.check_achievements_internal(p_user_id);
  end if;
  return jsonb_build_object('exam', to_jsonb(exam), 'xp_awarded', case when coalesce(award.awarded, false) then 20 else 0 end, 'achievements', achievements);
end;
$$;

create or replace function public.award_xp_for_verified_event_atomic(p_user_id uuid, p_source public.xp_source, p_source_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  reward integer;
  award record;
  achievements jsonb;
begin
  if p_source = 'task_completed' then
    if not exists (select 1 from public.tasks where id = p_source_id and user_id = p_user_id and status = 'completed' and completed_at is not null) then raise exception 'INVALID_TASK_EVENT'; end if;
    reward := 30;
  elsif p_source = 'study_session_completed' then
    if not exists (select 1 from public.study_sessions where id = p_source_id and user_id = p_user_id and completed and ended_at is not null and duration_seconds >= 60) then raise exception 'INVALID_SESSION_EVENT'; end if;
    reward := 25;
  elsif p_source = 'quiz_completed' then
    if not exists (select 1 from public.quizzes where id = p_source_id and user_id = p_user_id and status = 'completed' and completed_at is not null) then raise exception 'INVALID_QUIZ_EVENT'; end if;
    reward := 20;
  elsif p_source = 'exam_recorded' then
    if not exists (select 1 from public.exams where id = p_source_id and user_id = p_user_id and grade is not null and max_grade is not null and status in ('passed', 'failed')) then raise exception 'INVALID_EXAM_EVENT'; end if;
    reward := 20;
  else
    raise exception 'UNSUPPORTED_XP_SOURCE';
  end if;
  select * into award from public.award_xp_internal(p_user_id, p_source, p_source_id, reward, 'Actividad académica completada');
  achievements := public.check_achievements_internal(p_user_id);
  return jsonb_build_object('awarded', award.awarded, 'amount', case when award.awarded then reward else 0 end, 'current_streak', award.current_streak, 'achievements', achievements);
end;
$$;

create or replace function public.submit_quiz_atomic(p_user_id uuid, p_quiz_id uuid, p_answers jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  quiz public.quizzes%rowtype;
  question_count integer;
  submitted_count integer;
  distinct_count integer;
  correct_count integer;
  score_value numeric(5,2);
  award record;
  achievements jsonb;
  answer_payload jsonb;
begin
  if p_answers is null or jsonb_typeof(p_answers) <> 'array' then raise exception 'INVALID_QUIZ_ANSWERS'; end if;
  select * into quiz from public.quizzes where id = p_quiz_id and user_id = p_user_id for update;
  if not found then raise exception 'QUIZ_NOT_FOUND'; end if;

  select count(*) into question_count from public.quiz_questions where quiz_id = quiz.id;
  select count(*), count(distinct (item.value ->> 'question_id'))
  into submitted_count, distinct_count
  from jsonb_array_elements(p_answers) as item(value);
  if question_count = 0 or submitted_count <> question_count or distinct_count <> question_count then raise exception 'INCOMPLETE_QUIZ_ANSWERS'; end if;
  if exists (
    select 1
    from jsonb_array_elements(p_answers) as item(value)
    left join public.quiz_questions question on question.id = (item.value ->> 'question_id')::uuid and question.quiz_id = quiz.id
    where question.id is null
  ) then raise exception 'QUIZ_QUESTION_OWNERSHIP_FAILED'; end if;

  if quiz.status = 'completed' then
    select coalesce(jsonb_agg(jsonb_build_object('question_id', answer.question_id, 'is_correct', answer.is_correct, 'feedback', answer.feedback) order by question.position), '[]'::jsonb)
    into answer_payload
    from public.quiz_answers answer join public.quiz_questions question on question.id = answer.question_id
    where answer.quiz_id = quiz.id;
    return jsonb_build_object('score', quiz.score, 'correct_answers', (select count(*) from public.quiz_answers where quiz_id = quiz.id and is_correct), 'question_count', question_count, 'xp_awarded', 0, 'answers', answer_payload, 'achievements', '[]'::jsonb);
  end if;
  if quiz.status <> 'active' then raise exception 'QUIZ_NOT_ACTIVE'; end if;

  insert into public.quiz_answers(quiz_id, question_id, answer, is_correct, feedback)
  select quiz.id,
         question.id,
         item.value ->> 'answer',
         exists (
           select 1 from jsonb_array_elements_text(key.accepted_answers) accepted(value)
           where lower(regexp_replace(trim(accepted.value), '\s+', ' ', 'g')) = lower(regexp_replace(trim(item.value ->> 'answer'), '\s+', ' ', 'g'))
         ),
         case when exists (
           select 1 from jsonb_array_elements_text(key.accepted_answers) accepted(value)
           where lower(regexp_replace(trim(accepted.value), '\s+', ' ', 'g')) = lower(regexp_replace(trim(item.value ->> 'answer'), '\s+', ' ', 'g'))
         ) then '¡Correcto!' else coalesce(key.explanation, 'Repasá este concepto y volvé a intentarlo.') end
  from jsonb_array_elements(p_answers) as item(value)
  join public.quiz_questions question on question.id = (item.value ->> 'question_id')::uuid and question.quiz_id = quiz.id
  join public.quiz_answer_keys key on key.question_id = question.id
  on conflict (quiz_id, question_id) do update set answer = excluded.answer, is_correct = excluded.is_correct, feedback = excluded.feedback;

  select count(*) filter (where is_correct), count(*) into correct_count, question_count from public.quiz_answers where quiz_id = quiz.id;
  score_value := round((correct_count::numeric / question_count::numeric) * 100, 2);
  update public.quizzes set status = 'completed', score = score_value, completed_at = now() where id = quiz.id;
  select * into award from public.award_xp_internal(p_user_id, 'quiz_completed', quiz.id, 20 + correct_count * 5, 'Quiz completado: ' || score_value || '%');
  achievements := public.check_achievements_internal(p_user_id);
  select coalesce(jsonb_agg(jsonb_build_object('question_id', answer.question_id, 'is_correct', answer.is_correct, 'feedback', answer.feedback) order by question.position), '[]'::jsonb)
  into answer_payload
  from public.quiz_answers answer join public.quiz_questions question on question.id = answer.question_id
  where answer.quiz_id = quiz.id;
  return jsonb_build_object('score', score_value, 'correct_answers', correct_count, 'question_count', question_count, 'xp_awarded', case when award.awarded then 20 + correct_count * 5 else 0 end, 'answers', answer_payload, 'achievements', achievements);
end;
$$;

-- Backend-only RPCs: Edge Functions authenticate the user first, then call service_role.
grant execute on function public.check_achievements_internal(uuid) to service_role;
grant execute on function public.complete_task_atomic(uuid, uuid) to service_role;
grant execute on function public.complete_study_session_atomic(uuid, uuid, timestamptz, integer, public.study_mode) to service_role;
grant execute on function public.save_exam_atomic(uuid, uuid, text, uuid, timestamptz, numeric, numeric, numeric, text) to service_role;
grant execute on function public.award_xp_for_verified_event_atomic(uuid, public.xp_source, uuid) to service_role;
grant execute on function public.submit_quiz_atomic(uuid, uuid, jsonb) to service_role;
revoke all on function public.check_achievements_internal(uuid) from public, anon, authenticated;
revoke all on function public.complete_task_atomic(uuid, uuid) from public, anon, authenticated;
revoke all on function public.complete_study_session_atomic(uuid, uuid, timestamptz, integer, public.study_mode) from public, anon, authenticated;
revoke all on function public.save_exam_atomic(uuid, uuid, text, uuid, timestamptz, numeric, numeric, numeric, text) from public, anon, authenticated;
revoke all on function public.award_xp_for_verified_event_atomic(uuid, public.xp_source, uuid) from public, anon, authenticated;
revoke all on function public.submit_quiz_atomic(uuid, uuid, jsonb) from public, anon, authenticated;

-- ============================================================================
-- SECTION 3 — COMMIT
-- ============================================================================
commit;
