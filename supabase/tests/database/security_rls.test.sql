begin;
select plan(37);

-- Seed two real auth identities. The profile/streak trigger from the migration creates
-- their tenant roots; all test data remains inside this transaction and is rolled back.
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
 ('11111111-1111-4111-8111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-a@example.test', 'not-used-in-test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
 ('22222222-2222-4222-8222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-b@example.test', 'not-used-in-test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

insert into public.pets (id, user_id, species, name) values
 ('aaaaaaa1-aaaa-4aaa-8aaa-aaaaaaaaaaa1', '11111111-1111-4111-8111-111111111111', 'cat', 'Aster'),
 ('bbbbbbb2-bbbb-4bbb-8bbb-bbbbbbbbbbb2', '22222222-2222-4222-8222-222222222222', 'dog', 'Bongo');
insert into public.subjects (id, user_id, name) values
 ('aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3', '11111111-1111-4111-8111-111111111111', 'Materia de A'),
 ('bbbbbbb3-bbbb-4bbb-8bbb-bbbbbbbbbbb3', '22222222-2222-4222-8222-222222222222', 'Materia de B');
insert into public.notes (id, user_id, subject_id, title, content) values
 ('aaaaaaa4-aaaa-4aaa-8aaa-aaaaaaaaaaa4', '11111111-1111-4111-8111-111111111111', 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'Nota de A', 'Contenido privado');
insert into public.documents (id, user_id, subject_id, name, storage_path, mime_type, size_bytes) values
 ('aaaaaaa5-aaaa-4aaa-8aaa-aaaaaaaaaaa5', '11111111-1111-4111-8111-111111111111', 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'Documento A', '11111111-1111-4111-8111-111111111111/aaaaaaa5/documento.txt', 'text/plain', 10);
insert into public.tasks (id, user_id, subject_id, title) values
 ('aaaaaaa6-aaaa-4aaa-8aaa-aaaaaaaaaaa6', '11111111-1111-4111-8111-111111111111', 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'Tarea de A');
insert into public.ai_conversations (id, user_id, subject_id, note_id, title) values
 ('aaaaaaa7-aaaa-4aaa-8aaa-aaaaaaaaaaa7', '11111111-1111-4111-8111-111111111111', 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'aaaaaaa4-aaaa-4aaa-8aaa-aaaaaaaaaaa4', 'Conversación de A');
insert into public.quizzes (id, user_id, subject_id, title, status) values
 ('aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8', '11111111-1111-4111-8111-111111111111', 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'Quiz de A', 'active');
insert into public.quiz_questions (id, quiz_id, position, question_type, prompt, options) values
 ('aaaaaaa9-aaaa-4aaa-8aaa-aaaaaaaaaaa9', 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8', 1, 'multiple_choice', 'Pregunta privada 1', '["Correcta","Incorrecta","Otra","Más"]'::jsonb),
 ('aaaaaab0-aaaa-4aaa-8aaa-aaaaaaaaaab0', 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8', 2, 'multiple_choice', 'Pregunta privada 2', '["Correcta","Incorrecta","Otra","Más"]'::jsonb);
insert into public.quiz_answer_keys(question_id, accepted_answers) values
 ('aaaaaaa9-aaaa-4aaa-8aaa-aaaaaaaaaaa9', '["A"]'::jsonb),
 ('aaaaaab0-aaaa-4aaa-8aaa-aaaaaaaaaab0', '["A"]'::jsonb);
insert into public.xp_transactions (id, user_id, source, source_id, amount) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', '11111111-1111-4111-8111-111111111111', 'daily_goal_completed', 'aaaaaaa0-aaaa-4aaa-8aaa-aaaaaaaaaaa0', 10);
insert into public.notifications (id, user_id, title, body) values
 ('aaaaaaab-aaaa-4aaa-8aaa-aaaaaaaaaaab', '11111111-1111-4111-8111-111111111111', 'Privada', 'Sólo A puede verla');
insert into storage.objects (bucket_id, name, owner_id) values
 ('documents', '11111111-1111-4111-8111-111111111111/aaaaaaa5/documento.txt', '11111111-1111-4111-8111-111111111111');

set local role authenticated;
select set_config('request.jwt.claim.role', 'authenticated', true);
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select is((select count(*)::integer from public.subjects), 1, 'A only reads A subjects');
select is((select count(*)::integer from public.notes), 1, 'A only reads A notes');
select is((select count(*)::integer from public.documents), 1, 'A only reads A documents');
select is((select count(*)::integer from public.ai_conversations), 1, 'A only reads A conversations');
select is((select count(*)::integer from public.quizzes), 1, 'A only reads A quizzes');
select is((select count(*)::integer from public.xp_transactions), 1, 'A only reads A XP ledger');
select is((select count(*)::integer from public.pets), 1, 'A only reads A pet');
select is((select count(*)::integer from storage.objects where bucket_id = 'documents'), 1, 'A only reads objects in A folder');

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select is((select count(*)::integer from public.subjects where id = 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3'), 0, 'B cannot read A subject');
select is((select count(*)::integer from public.notes where id = 'aaaaaaa4-aaaa-4aaa-8aaa-aaaaaaaaaaa4'), 0, 'B cannot read A note');
select is((select count(*)::integer from public.documents where id = 'aaaaaaa5-aaaa-4aaa-8aaa-aaaaaaaaaaa5'), 0, 'B cannot read A document');
select is((select count(*)::integer from public.ai_conversations where id = 'aaaaaaa7-aaaa-4aaa-8aaa-aaaaaaaaaaa7'), 0, 'B cannot read A conversation');
select is((select count(*)::integer from public.quizzes where id = 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8'), 0, 'B cannot read A quiz');
select is((select count(*)::integer from public.xp_transactions where user_id = '11111111-1111-4111-8111-111111111111'), 0, 'B cannot read A XP');
select is((select count(*)::integer from public.pets where user_id = '11111111-1111-4111-8111-111111111111'), 0, 'B cannot read A pet');
select is((select count(*)::integer from storage.objects where bucket_id = 'documents'), 0, 'B cannot read A Storage object');

update public.subjects set name = 'Mutated by B' where id = 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3';
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select is((select name from public.subjects where id = 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3'), 'Materia de A', 'B cannot modify A subject');
select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
delete from public.notes where id = 'aaaaaaa4-aaaa-4aaa-8aaa-aaaaaaaaaaa4';
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select is((select count(*)::integer from public.notes where id = 'aaaaaaa4-aaaa-4aaa-8aaa-aaaaaaaaaaa4'), 1, 'B cannot delete A note');

select set_config('request.jwt.claim.sub', '22222222-2222-4222-8222-222222222222', true);
select throws_ok(
  $$insert into public.notes(user_id, subject_id, title, content) values ('22222222-2222-4222-8222-222222222222', 'aaaaaaa3-aaaa-4aaa-8aaa-aaaaaaaaaaa3', 'Cross tenant', 'No debe entrar')$$,
  '23514', 'Referenced subject must belong to the same user',
  'Cross-user subject reference is rejected by a database trigger'
);
select throws_ok(
  $$insert into public.tasks(user_id, title, status, completed_at) values ('22222222-2222-4222-8222-222222222222', 'XP falso', 'completed', now())$$,
  '42501', null,
  'Authenticated clients cannot self-create completed task events'
);
select throws_ok(
  $$insert into public.xp_transactions(user_id, source, source_id, amount) values ('22222222-2222-4222-8222-222222222222', 'task_completed', 'bbbbbbb0-bbbb-4bbb-8bbb-bbbbbbbbbbb0', 999)$$,
  '42501', null,
  'Authenticated clients cannot insert arbitrary XP'
);
select set_config('request.jwt.claim.sub', '11111111-1111-4111-8111-111111111111', true);
select throws_ok(
  $$update public.notifications set title = 'Manipulada' where id = 'aaaaaaab-aaaa-4aaa-8aaa-aaaaaaaaaaab'$$,
  '42501', null,
  'A client cannot alter notification content'
);
select lives_ok(
  $$update public.notifications set read_at = now() where id = 'aaaaaaab-aaaa-4aaa-8aaa-aaaaaaaaaaab'$$,
  'A client can mark its notification as read'
);
select ok((select read_at is not null from public.notifications where id = 'aaaaaaab-aaaa-4aaa-8aaa-aaaaaaaaaaab'), 'Read marker was updated without changing content');

set local role service_role;
select lives_ok(
  $$select public.complete_task_atomic('11111111-1111-4111-8111-111111111111', 'aaaaaaa6-aaaa-4aaa-8aaa-aaaaaaaaaaa6')$$,
  'Server completion is allowed'
);
select is((select count(*)::integer from public.xp_transactions where user_id = '11111111-1111-4111-8111-111111111111' and source = 'task_completed' and source_id = 'aaaaaaa6-aaaa-4aaa-8aaa-aaaaaaaaaaa6'), 1, 'Task completion creates one XP transaction');
select lives_ok(
  $$select public.complete_task_atomic('11111111-1111-4111-8111-111111111111', 'aaaaaaa6-aaaa-4aaa-8aaa-aaaaaaaaaaa6')$$,
  'Task completion retry is safe'
);
select is((select count(*)::integer from public.xp_transactions where user_id = '11111111-1111-4111-8111-111111111111' and source = 'task_completed' and source_id = 'aaaaaaa6-aaaa-4aaa-8aaa-aaaaaaaaaaa6'), 1, 'Retry does not duplicate XP');

select lives_ok(
  $$insert into public.attendance_records(user_id, subject_id, attendance_date) values ('11111111-1111-4111-8111-111111111111', null, current_date)$$,
  'A general attendance row can be created'
);
select throws_ok(
  $$insert into public.attendance_records(user_id, subject_id, attendance_date) values ('11111111-1111-4111-8111-111111111111', null, current_date)$$,
  '23505', null,
  'A second general attendance row is rejected despite NULL subject'
);

select throws_ok(
  $$select public.submit_quiz_atomic('11111111-1111-4111-8111-111111111111', 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8', jsonb_build_array(jsonb_build_object('question_id', 'aaaaaaa9-aaaa-4aaa-8aaa-aaaaaaaaaaa9', 'answer', 'A')))$$,
  'P0001', 'INCOMPLETE_QUIZ_ANSWERS',
  'Incomplete quiz submission rolls back completely'
);
select is((select status::text from public.quizzes where id = 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8'), 'active', 'Quiz remains active after rejected submission');
select lives_ok(
  $$select public.submit_quiz_atomic('11111111-1111-4111-8111-111111111111', 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8', jsonb_build_array(jsonb_build_object('question_id', 'aaaaaaa9-aaaa-4aaa-8aaa-aaaaaaaaaaa9', 'answer', 'A'), jsonb_build_object('question_id', 'aaaaaab0-aaaa-4aaa-8aaa-aaaaaaaaaab0', 'answer', 'A')))$$,
  'Complete quiz is submitted atomically'
);
select is((select count(*)::integer from public.quiz_answers where quiz_id = 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8'), 2, 'Quiz answers are saved once');
select is((select count(*)::integer from public.xp_transactions where user_id = '11111111-1111-4111-8111-111111111111' and source = 'quiz_completed' and source_id = 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8'), 1, 'Quiz completion creates one XP transaction');
select lives_ok(
  $$select public.submit_quiz_atomic('11111111-1111-4111-8111-111111111111', 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8', jsonb_build_array(jsonb_build_object('question_id', 'aaaaaaa9-aaaa-4aaa-8aaa-aaaaaaaaaaa9', 'answer', 'A'), jsonb_build_object('question_id', 'aaaaaab0-aaaa-4aaa-8aaa-aaaaaaaaaab0', 'answer', 'A')))$$,
  'Completed quiz retry returns the prior result'
);
select is((select count(*)::integer from public.xp_transactions where user_id = '11111111-1111-4111-8111-111111111111' and source = 'quiz_completed' and source_id = 'aaaaaaa8-aaaa-4aaa-8aaa-aaaaaaaaaaa8'), 1, 'Quiz retry does not duplicate XP');

select * from finish();
rollback;
