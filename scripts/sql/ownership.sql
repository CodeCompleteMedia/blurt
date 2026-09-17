\set ON_ERROR_STOP off
\pset pager off
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'teacher@school'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'student-with-an-account@school');

select '--- a student with only the anon key can no longer open a room ---' as t;
select public.create_game('11111111-1111-1111-1111-111111111111');

select '--- and neither can a signed-in teacher host the ownerless template ---' as t;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);
select public.create_game('11111111-1111-1111-1111-111111111111');

select '--- but they get their own copy, and can host that ---' as t;
select public.copy_sample_quiz() as mine \gset
select count(*) as questions_copied from public.questions where quiz_id = :'mine';
select code is not null as room_opened from public.create_game(:'mine');

select '--- a student who makes an account still cannot host the teacher''s quiz ---' as t;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false);
select public.create_game(:'mine');
select public.duplicate_quiz(:'mine');

select '--- row level security: what each of them can see ---' as t;
set role authenticated;
select count(*) as student_account_sees_quizzes from public.quizzes;
select count(*) as student_account_sees_questions from public.questions;
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);
select count(*) as teacher_sees_quizzes from public.quizzes;
select count(*) as teacher_sees_questions from public.questions;

select '--- the teacher cannot write into someone else''s name ---' as t;
insert into public.quizzes (title, owner_id) values ('planted', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select '--- reordering: swapping two positions in one statement ---' as t;
update public.questions q set position = case position when 0 then 1 when 1 then 0 else position end
where quiz_id = :'mine';
select position, left(text, 30) as text from public.questions where quiz_id = :'mine' order by position limit 2;

reset role;
set role anon;
select '--- anon: quizzes and questions ---' as t;
select count(*) from public.quizzes;
select count(*) from public.questions;
