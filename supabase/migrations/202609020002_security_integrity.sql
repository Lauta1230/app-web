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

-- The browser may edit safe task fields, but cannot insert tasks directly, choose a
-- task owner, self-mark completion, or manufacture completed study/exam events.
-- Task creation and every protected state transition are server-side below.
revoke insert, update on public.tasks from anon, authenticated;
grant update (subject_id, title, description, priority, due_at) on public.tasks to authenticated;
revoke insert, update on public.study_sessions from anon, authenticated;
revoke insert, update on public.exams from anon, authenticated;
revoke update on public.notifications from anon, authenticated;
grant update (read_at) on public.notifications to authenticated;

-- Keep Storage UPDATE as narrow as its SELECT/INSERT/DELETE policies. A caller cannot
-- move an object to a different bucket or another user's folder through an update.
drop policy if exists "private files update own folder" on storage.objects;
create policy "private files update own folder" on storage.objects for update to authenticated
using (
  bucket_id in ('documents', 'avatars', 'audio')
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id in ('documents', 'avatars', 'audio')
  and (storage.foldername(name))[1] = auth.uid()::text
);

-- The client can request a task, but never supplies its authoritative owner. This
-- RPC derives it from auth.uid(), validates the selected subject and inserts only a
-- pending task. It is security definer because direct INSERT was revoked above.
create or replace function public.create_task_atomic(
  p_subject_id uuid,
  p_title text,
  p_description text,
  p_priority public.task_priority,
  p_due_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  actor_id uuid := auth.uid();
  task public.tasks%rowtype;
begin
  if actor_id is null then raise exception 'UNAUTHORIZED'; end if;
  if char_length(trim(coalesce(p_title, ''))) not between 1 and 180 then raise exception 'INVALID_TASK_TITLE'; end if;
  if p_description is not null and char_length(p_description) > 30000 then raise exception 'INVALID_TASK_DESCRIPTION'; end if;
  if p_priority is null then raise exception 'INVALID_TASK_PRIORITY'; end if;
  if p_subject_id is not null and not exists (
    select 1 from public.subjects subject where subject.id = p_subject_id and subject.user_id = actor_id
  ) then
    raise exception 'INVALID_TASK_SUBJECT';
  end if;
  insert into public.tasks(user_id, subject_id, title, description, priority, due_at)
  values(actor_id, p_subject_id, trim(p_title), p_description, p_priority, p_due_at)
  returning * into task;
  return to_jsonb(task);
end;
$$;

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
  if p_subject_id is not null and not exists (
    select 1 from public.subjects subject where subject.id = p_subject_id and subject.user_id = p_user_id
  ) then
    raise exception 'INVALID_SESSION_SUBJECT';
  end if;
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
  if p_subject_id is not null and not exists (
    select 1 from public.subjects subject where subject.id = p_subject_id and subject.user_id = p_user_id
  ) then
    raise exception 'INVALID_EXAM_SUBJECT';
  end if;

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
  answer_key_count integer;
  submitted_count integer;
  distinct_count integer;
  persisted_count integer;
  correct_count integer;
  score_value numeric(5,2);
  award record;
  achievements jsonb;
  answer_payload jsonb;
begin
  if p_answers is null or jsonb_typeof(p_answers) <> 'array' then raise exception 'INVALID_QUIZ_ANSWERS'; end if;
  select * into quiz from public.quizzes where id = p_quiz_id and user_id = p_user_id for update;
  if not found then raise exception 'QUIZ_NOT_FOUND'; end if;

  -- A quiz can only be marked complete if its question/answer-key set is complete.
  -- quiz_answer_keys.question_id is a primary key, so this equality proves exactly
  -- one key exists for every question in this quiz and no question is unkeyed.
  select count(*) into question_count from public.quiz_questions where quiz_id = quiz.id;
  if question_count = 0 then raise exception 'QUIZ_HAS_NO_QUESTIONS'; end if;
  select count(*) into answer_key_count
  from public.quiz_questions question
  join public.quiz_answer_keys answer_key on answer_key.question_id = question.id
  where question.quiz_id = quiz.id;
  if answer_key_count <> question_count then raise exception 'QUIZ_ANSWER_KEY_INTEGRITY_FAILED'; end if;

  -- Validate JSON shape before UUID casts, then prove a one-to-one correspondence
  -- between received answers and the questions belonging to this exact quiz.
  if exists (
    select 1 from jsonb_array_elements(p_answers) as item(value)
    where jsonb_typeof(item.value) <> 'object'
       or jsonb_typeof(item.value -> 'question_id') <> 'string'
       or jsonb_typeof(item.value -> 'answer') <> 'string'
       or char_length(item.value ->> 'answer') > 5000
  ) then
    raise exception 'INVALID_QUIZ_ANSWERS';
  end if;
  select count(*), count(distinct (item.value ->> 'question_id'))
  into submitted_count, distinct_count
  from jsonb_array_elements(p_answers) as item(value);
  if submitted_count <> question_count then raise exception 'INCOMPLETE_QUIZ_ANSWERS'; end if;
  if distinct_count <> question_count then raise exception 'DUPLICATE_QUIZ_ANSWERS'; end if;
  if exists (
    select 1
    from jsonb_array_elements(p_answers) as item(value)
    left join public.quiz_questions question
      on question.id = case
        when (item.value ->> 'question_id') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
          then (item.value ->> 'question_id')::uuid
        else null
      end
      and question.quiz_id = quiz.id
    where question.id is null
  ) then
    raise exception 'QUIZ_QUESTION_OWNERSHIP_FAILED';
  end if;

  -- Completed retries are safe only after validating the same complete answer set.
  if quiz.status = 'completed' then
    select coalesce(jsonb_agg(jsonb_build_object('question_id', answer.question_id, 'is_correct', answer.is_correct, 'feedback', answer.feedback) order by question.position), '[]'::jsonb)
    into answer_payload
    from public.quiz_answers answer join public.quiz_questions question on question.id = answer.question_id
    where answer.quiz_id = quiz.id;
    return jsonb_build_object('score', quiz.score, 'correct_answers', (select count(*) from public.quiz_answers where quiz_id = quiz.id and is_correct), 'question_count', question_count, 'xp_awarded', 0, 'answers', answer_payload, 'achievements', '[]'::jsonb);
  end if;
  if quiz.status <> 'active' then raise exception 'QUIZ_NOT_ACTIVE'; end if;
  if exists (select 1 from public.quiz_answers where quiz_id = quiz.id) then raise exception 'QUIZ_ALREADY_HAS_ANSWERS'; end if;

  insert into public.quiz_answers(quiz_id, question_id, answer, is_correct, feedback)
  select quiz.id,
         question.id,
         item.value ->> 'answer',
         exists (
           select 1 from jsonb_array_elements_text(answer_key.accepted_answers) accepted(value)
           where lower(regexp_replace(trim(accepted.value), '\s+', ' ', 'g')) = lower(regexp_replace(trim(item.value ->> 'answer'), '\s+', ' ', 'g'))
         ),
         case when exists (
           select 1 from jsonb_array_elements_text(answer_key.accepted_answers) accepted(value)
           where lower(regexp_replace(trim(accepted.value), '\s+', ' ', 'g')) = lower(regexp_replace(trim(item.value ->> 'answer'), '\s+', ' ', 'g'))
         ) then '¡Correcto!' else coalesce(answer_key.explanation, 'Repasá este concepto y volvé a intentarlo.') end
  from jsonb_array_elements(p_answers) as item(value)
  join public.quiz_questions question on question.id = (item.value ->> 'question_id')::uuid and question.quiz_id = quiz.id
  join public.quiz_answer_keys answer_key on answer_key.question_id = question.id;

  -- Recheck persisted rows before scoring. No subset can be scored or completed.
  select count(*) filter (where is_correct), count(*)
  into correct_count, persisted_count
  from public.quiz_answers
  where quiz_id = quiz.id;
  if persisted_count <> question_count then raise exception 'QUIZ_ANSWER_PERSISTENCE_FAILED'; end if;
  score_value := round((correct_count::numeric / question_count::numeric) * 100, 2);
  update public.quizzes set status = 'completed', score = score_value, completed_at = now() where id = quiz.id and status = 'active';
  if not found then raise exception 'QUIZ_COMPLETION_STATE_CHANGED'; end if;
  select * into award from public.award_xp_internal(p_user_id, 'quiz_completed', quiz.id, 20 + correct_count * 5, 'Quiz completado: ' || score_value || '%');
  achievements := public.check_achievements_internal(p_user_id);
  select coalesce(jsonb_agg(jsonb_build_object('question_id', answer.question_id, 'is_correct', answer.is_correct, 'feedback', answer.feedback) order by question.position), '[]'::jsonb)
  into answer_payload
  from public.quiz_answers answer join public.quiz_questions question on question.id = answer.question_id
  where answer.quiz_id = quiz.id;
  return jsonb_build_object('score', score_value, 'correct_answers', correct_count, 'question_count', question_count, 'xp_awarded', case when award.awarded then 20 + correct_count * 5 else 0 end, 'answers', answer_payload, 'achievements', achievements);
end;
$$;

-- Task creation is callable by authenticated users but derives its actor only from
-- auth.uid(). The remaining RPCs stay backend-only: Edge Functions authenticate the
-- user first, then call them through service_role.
revoke all on function public.create_task_atomic(uuid, text, text, public.task_priority, timestamptz) from public, anon, authenticated;
grant execute on function public.create_task_atomic(uuid, text, text, public.task_priority, timestamptz) to authenticated;
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
