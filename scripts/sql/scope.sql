-- A report must only ever count its own game.
--
-- This is the check that 0026 exists for. Two teachers, two games, the same
-- question in the same position: one room full of wrong answers, and one room
-- with a single student who got it right. The second teacher's report must say
-- there was no miss.
--
-- The bug this replaces reported the *other* room's wrong answers as its own,
-- and it survived every earlier check because no earlier check ever put two
-- games in the database at once.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

insert into public.quizzes (id, title, owner_id) values
  ('55555555-5555-5555-5555-555555555555', 'Mine', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'),
  ('66666666-6666-6666-6666-666666666666', 'Theirs', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
insert into public.questions (quiz_id, position, kind, text, choices, correct_index, seconds, blurt_enabled)
select id, 0, 'choice', 'Pick', array['right','wrong','other'], 0, 15, false
from public.quizzes where id in (
  '55555555-5555-5555-5555-555555555555', '66666666-6666-6666-6666-666666666666');

-- The other teacher's room: three students, all wrong.
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false) \gset x
select code as tcode, host_token as ttok
from public.create_game('66666666-6666-6666-6666-666666666666') \gset
select public.advance_game(:'ttok') \gset x
select player_token as t1 from public.join_game(:'tcode', 'T1') \gset
select player_token as t2 from public.join_game(:'tcode', 'T2') \gset
select player_token as t3 from public.join_game(:'tcode', 'T3') \gset
select public.submit_answer(:'t1', 1) \gset x
select public.submit_answer(:'t2', 1) \gset x
select public.submit_answer(:'t3', 1) \gset x

-- Our room: one student, correct.
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select code as mcode, host_token as mtok
from public.create_game('55555555-5555-5555-5555-555555555555') \gset
select public.advance_game(:'mtok') \gset x
select player_token as mine from public.join_game(:'mcode', 'Solo') \gset
select public.submit_answer(:'mine', 0) \gset x

do $$
declare r record;
begin
  select * into r from public.game_report(
    (select id from public.games where code = (
      select code from public.games g join public.quizzes z on z.id = g.quiz_id
      where z.title = 'Mine')));

  if r.answered <> 1 or r.correct <> 1 then
    raise exception 'expected 1/1 in our own room, got %/%', r.correct, r.answered;
  end if;
  if r.common_wrong is not null then
    raise exception 'another game bled in: reported "% x%" as our most common miss',
      r.common_wrong, r.common_wrong_count;
  end if;
  raise notice 'ok  one student, right answer, no miss reported';
end $$;

-- And the other teacher still sees their own three, so the filter did not simply
-- switch the column off.
do $$
declare r record;
begin
  perform set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false);
  select * into r from public.game_report(
    (select g.id from public.games g join public.quizzes z on z.id = g.quiz_id
     where z.title = 'Theirs'));
  if r.common_wrong is distinct from 'wrong' or r.common_wrong_count <> 3 then
    raise exception 'their own miss should be wrong x3, got % x%',
      r.common_wrong, r.common_wrong_count;
  end if;
  raise notice 'ok  their room still reports its own three';
end $$;
