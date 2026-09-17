-- What a report says about a game that went four questions and was abandoned.
--
-- The fixture is built so each question has a different shape: q1 everyone
-- right, q2 everyone wrong the *same* way (a bad question), q3 they scatter (a
-- hard one), q4 only one student answers, q5 never asked. A report that cannot
-- tell those apart is not worth reading.
--
-- This file used to print the tables for eyeballing, with ON_ERROR_STOP off, so
-- nothing in it could fail — including the four "another teacher sees none of
-- it" checks at the end. It asserts now.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select public.copy_sample_quiz() as quiz \gset
select code, host_token from public.create_game(:'quiz') \gset
select public.update_game_settings(:'host_token', false) \gset x
select player_id, player_token from public.join_game(:'code', 'Ana') \gset a_
select player_id, player_token from public.join_game(:'code', 'Ben') \gset b_
select player_id, player_token from public.join_game(:'code', 'Cara') \gset c_

-- Correct answers in the sample quiz: 1, 1, 2, 1, 1.
select public.advance_game(:'host_token') \gset x
select public.submit_answer(:'a_player_token', 1) \gset x
select public.submit_answer(:'b_player_token', 1) \gset x
select public.submit_answer(:'c_player_token', 1) \gset x

select public.advance_game(:'host_token') \gset x
select public.submit_answer(:'a_player_token', 3) \gset x
select public.submit_answer(:'b_player_token', 3) \gset x
select public.submit_answer(:'c_player_token', 3) \gset x

select public.advance_game(:'host_token') \gset x
select public.submit_answer(:'a_player_token', 2) \gset x
select public.submit_answer(:'b_player_token', 0) \gset x
select public.submit_answer(:'c_player_token', 1) \gset x

select public.advance_game(:'host_token') \gset x
select public.submit_answer(:'a_player_token', 1) \gset x
select public.advance_game(:'host_token') \gset x
select public.advance_game(:'host_token') \gset x

select set_config('blurt.code', :'code', false) \gset x

do $$
declare
  v_game uuid := (select id from public.games where code = current_setting('blurt.code'));
  r record;
  n int;
begin
  select count(*) into n from public.game_report(v_game);
  if n <> 4 then
    raise exception 'four questions were asked, report has % rows (q5 must be absent)', n;
  end if;

  -- Hardest first is the whole point: the question nobody got must be on top.
  select * into r from public.game_report(v_game) limit 1;
  if r.percent_correct <> 0 or r.answered <> 3 then
    raise exception 'top row should be the 0%% question with 3 answers, got %%%/%',
      r.percent_correct, r.answered;
  end if;
  -- All three went the same wrong way. That is what makes it a bad question
  -- rather than a hard one, and the count is how a reader can tell.
  if r.common_wrong_count <> 3 then
    raise exception 'unanimous wrong answer should count 3, got %', r.common_wrong_count;
  end if;

  -- Everyone right: there is no miss to name.
  select * into r from public.game_report(v_game) where q_position = 0;
  if r.correct <> 3 or r.answered <> 3 or r.percent_correct <> 100 then
    raise exception 'q1 should be 3/3 100%%, got %/% %%%', r.correct, r.answered, r.percent_correct;
  end if;
  if r.common_wrong is not null then
    raise exception 'q1 was answered correctly by everyone, yet reports miss "%"', r.common_wrong;
  end if;

  -- Scattered: two students wrong in two different ways, so the most common
  -- miss is only one student deep.
  select * into r from public.game_report(v_game) where q_position = 2;
  if r.correct <> 1 or r.answered <> 3 then
    raise exception 'q3 should be 1/3, got %/%', r.correct, r.answered;
  end if;
  if r.common_wrong_count <> 1 then
    raise exception 'q3 misses were scattered, so the top miss should count 1, got %',
      r.common_wrong_count;
  end if;

  -- One answer, and a median that came from it rather than from zero.
  select * into r from public.game_report(v_game) where q_position = 3;
  if r.answered <> 1 or r.correct <> 1 then
    raise exception 'q4 should be 1/1, got %/%', r.correct, r.answered;
  end if;

  raise notice 'ok  four questions, hardest first, bad/hard/unanswered told apart';
end $$;

do $$
declare r record; n int;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);

  select * into r from public.game_players(
    (select id from public.games where code = current_setting('blurt.code')))
  where player_name = 'Ana';
  if r.place <> 1 or r.answered <> 4 or r.correct <> 3 then
    raise exception 'Ana answered 4 and got 3, in first; got place % %/%',
      r.place, r.correct, r.answered;
  end if;
  -- She missed only q2, and q2 alone.
  if r.missed <> array[1] then
    raise exception 'Ana should have missed question index 1 only, got %', r.missed;
  end if;

  select * into r from public.game_players(
    (select id from public.games where code = current_setting('blurt.code')))
  where player_name = 'Ben';
  if r.answered <> 3 then
    raise exception 'Ben answered 3 questions, report says %', r.answered;
  end if;

  select * into r from public.game_summary(
    (select id from public.games where code = current_setting('blurt.code')));
  if r.finished or r.players <> 3 or r.questions_asked <> 4 or r.questions_total <> 5 then
    raise exception 'summary wrong: finished=% players=% asked=% total=%',
      r.finished, r.players, r.questions_asked, r.questions_total;
  end if;

  select count(*) into n from public.my_games();
  if n <> 1 then raise exception 'the owner should see 1 game, sees %', n; end if;

  raise notice 'ok  students, summary and the games list agree with the fixture';
end $$;

-- The part that could never have failed before: everything is gated on owning
-- the game, and the other teacher owns nothing.
do $$
declare
  v_game uuid := (select id from public.games where code = current_setting('blurt.code'));
  n int;
  blocked int := 0;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false);

  select count(*) into n from public.my_games();
  if n <> 0 then raise exception 'another teacher sees % of my games', n; end if;

  -- insufficient_privilege specifically, not `when others`: a function that
  -- crashed on a syntax error would also "raise", and that is not a refusal.
  begin perform public.game_report(v_game);
  exception when insufficient_privilege then blocked := blocked + 1; end;
  begin perform public.game_players(v_game);
  exception when insufficient_privilege then blocked := blocked + 1; end;
  begin perform public.game_summary(v_game);
  exception when insufficient_privilege then blocked := blocked + 1; end;
  begin perform public.delete_game(v_game);
  exception when insufficient_privilege then blocked := blocked + 1; end;

  if blocked <> 4 then
    raise exception 'all four should refuse another teacher with insufficient_privilege; only % did', blocked;
  end if;

  if not exists (select 1 from public.games where id = v_game) then
    raise exception 'delete_game destroyed a game belonging to someone else';
  end if;

  raise notice 'ok  report, students, summary and delete all refuse another teacher';
end $$;
