-- The streak bonus: 100 for two in a row, 200 for three, nothing for the first.
--
-- The rule that matters is what breaks a run. Getting one wrong breaks it, and
-- so does not answering at all — otherwise a student could protect a streak by
-- sitting out the questions they were unsure of, which is the opposite of what
-- the bonus is for.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x

do $$
declare
  v_quiz uuid := public.copy_sample_quiz();
  g record; streaky record; skipper record; filler record; r record; r2 record;
  v_host uuid; v_code text;
  v_score int; v_accounted int;
begin
  select * into g from public.create_game(v_quiz);
  v_host := g.host_token; v_code := g.code;
  perform public.update_game_settings(v_host, false);   -- no recall, to keep this short
  select * into streaky from public.join_game(v_code, 'Streaky');
  select * into skipper from public.join_game(v_code, 'Skipper');
  select * into filler  from public.join_game(v_code, 'Filler');

  -- Correct answers in the sample quiz: 1, 1, 2, 1, 1.
  -- Streaky answers right, right, right, WRONG, right.
  -- Skipper answers question 1, sits out question 2, then answers again.

  -- q1 -----------------------------------------------------------------
  perform public.advance_game(v_host);
  perform public.submit_answer(streaky.player_token, 1);
  perform public.submit_answer(skipper.player_token, 1);
  perform public.advance_game(v_host); perform public.advance_game(v_host);

  select * into r from public.my_result(streaky.player_token);
  if not r.correct or r.streak <> 1 or r.bonus <> 0 then
    raise exception 'q1: a first right answer is streak 1 and no bonus; got correct=% streak=% bonus=%',
      r.correct, r.streak, r.bonus;
  end if;

  -- q2 -----------------------------------------------------------------
  perform public.advance_game(v_host);
  perform public.submit_answer(streaky.player_token, 1);   -- Skipper sits this one out
  perform public.advance_game(v_host); perform public.advance_game(v_host);

  select * into r from public.my_result(streaky.player_token);
  if r.streak <> 2 or r.bonus <> 100 then
    raise exception 'q2: two in a row is streak 2 worth 100; got streak=% bonus=%', r.streak, r.bonus;
  end if;

  -- q3 -----------------------------------------------------------------
  perform public.advance_game(v_host);
  perform public.submit_answer(streaky.player_token, 2);
  perform public.submit_answer(skipper.player_token, 2);
  perform public.advance_game(v_host); perform public.advance_game(v_host);

  select * into r  from public.my_result(streaky.player_token);
  select * into r2 from public.my_result(skipper.player_token);
  if r.streak <> 3 or r.bonus <> 200 then
    raise exception 'q3: three in a row is streak 3 worth 200; got streak=% bonus=%', r.streak, r.bonus;
  end if;
  -- The whole point: Skipper was right on q1 and right again here, but sat out
  -- the one in between, so this is a new run rather than a continued one.
  if not r2.correct or r2.streak <> 1 or r2.bonus <> 0 then
    raise exception 'q3: skipping a question must break a run; Skipper got streak=% bonus=%',
      r2.streak, r2.bonus;
  end if;

  -- q4: wrong ------------------------------------------------------------
  perform public.advance_game(v_host);
  perform public.submit_answer(streaky.player_token, 0);
  perform public.advance_game(v_host); perform public.advance_game(v_host);

  select * into r from public.my_result(streaky.player_token);
  if r.correct or r.streak <> 0 or r.bonus <> 0 then
    raise exception 'q4: a wrong answer ends the run; got correct=% streak=% bonus=%',
      r.correct, r.streak, r.bonus;
  end if;

  -- q5: and it begins again from nothing ---------------------------------
  perform public.advance_game(v_host);
  perform public.submit_answer(streaky.player_token, 1);
  perform public.advance_game(v_host); perform public.advance_game(v_host);

  select * into r from public.my_result(streaky.player_token);
  if not r.correct or r.streak <> 1 or r.bonus <> 0 then
    raise exception 'q5: a run restarts at 1 with no bonus; got streak=% bonus=%', r.streak, r.bonus;
  end if;

  -- Nothing unaccounted for: the score on the row is exactly what the answers
  -- and the bonuses add up to, with a wrong blurt's penalty not double-counted.
  select p.score, sum(greatest(a.awarded, 0)) + sum(a.bonus)
    into v_score, v_accounted
  from public.players p join public.answers a on a.player_id = p.id
  where p.id = streaky.player_id group by p.score;

  if v_score <> v_accounted then
    raise exception 'score is %, but the answers and bonuses add up to %', v_score, v_accounted;
  end if;

  raise notice 'ok  bonus at 2 and 3, broken by a wrong answer and by sitting one out';
end $$;

do $$
declare
  v_quiz uuid := (select id from public.quizzes
                  where owner_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' limit 1);
  g record; plain record; r record;
begin
  select * into g from public.create_game(v_quiz);
  -- Last argument is the streak bonus, turned off.
  perform public.update_game_settings(g.host_token, false, null, null, null, null, null, null, false);
  select * into plain from public.join_game(g.code, 'Plain');
  perform public.join_game(g.code, 'Other');

  perform public.advance_game(g.host_token);
  perform public.submit_answer(plain.player_token, 1);
  perform public.advance_game(g.host_token); perform public.advance_game(g.host_token);
  perform public.advance_game(g.host_token);
  perform public.submit_answer(plain.player_token, 1);
  perform public.advance_game(g.host_token); perform public.advance_game(g.host_token);

  select * into r from public.my_result(plain.player_token);
  if not r.correct then raise exception 'the second answer should still be correct'; end if;
  if r.bonus <> 0 then
    raise exception 'the bonus is switched off, yet a second right answer paid %', r.bonus;
  end if;

  raise notice 'ok  with the setting off, two in a row pays nothing extra';
end $$;
