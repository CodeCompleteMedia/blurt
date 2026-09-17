-- Blurting is a per-question choice, and the game setting is a master switch.
--
-- A question that opted out must open straight into its choices, and the floor
-- must not be claimable on it — a blurt makes no sense on "type the answer",
-- where the answer is typed rather than spoken.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x

insert into public.quizzes (id, title, owner_id) values
  ('33333333-3333-3333-3333-333333333333', 'Mixed', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
insert into public.questions (quiz_id, position, kind, text, choices, correct_index, accepted, seconds, blurt_enabled) values
  ('33333333-3333-3333-3333-333333333333', 0, 'choice', 'Blurtable',     array['a','b'], 0, null, 15, true),
  ('33333333-3333-3333-3333-333333333333', 1, 'choice', 'Not blurtable', array['a','b'], 1, null, 15, false),
  ('33333333-3333-3333-3333-333333333333', 2, 'text',   'Typed',         null, null, array['x'], 15, false);

do $$
declare
  v_quiz uuid := '33333333-3333-3333-3333-333333333333';
  g record; rosa record; r record;
  v_phase text;
  v_claimed boolean;
begin
  select * into g from public.create_game(v_quiz);
  select * into rosa from public.join_game(g.code, 'Rosa');

  -- Question 1 asked for a recall window, so it gets one.
  perform public.advance_game(g.host_token);
  select gg.phase into v_phase from public.games gg where gg.code = g.code;
  if v_phase <> 'recall' then
    raise exception 'q1 opted into blurting but opened in phase %', v_phase;
  end if;

  perform public.advance_game(g.host_token);            -- recall -> question_open
  perform public.submit_answer(rosa.player_token, 0);
  perform public.advance_game(g.host_token);            -- results -> q2

  -- Question 2 opted out, so there is no window to sit through.
  select gg.phase, gg.question_index into r from public.games gg where gg.code = g.code;
  if r.question_index <> 1 or r.phase <> 'question_open' then
    raise exception 'q2 opted out of blurting but opened at question % in phase %',
      r.question_index, r.phase;
  end if;

  -- And the floor cannot be claimed on it. Either answer is acceptable — a
  -- refusal or a false — as long as the phase does not move.
  begin
    v_claimed := public.blurt(rosa.player_token);
  exception when others then
    v_claimed := false;
  end;
  select gg.phase into v_phase from public.games gg where gg.code = g.code;
  if v_claimed or v_phase <> 'question_open' then
    raise exception 'the floor was claimed on a question that opted out (claimed=% phase=%)',
      v_claimed, v_phase;
  end if;

  perform public.submit_answer(rosa.player_token, 0);
  perform public.advance_game(g.host_token);            -- results -> q3, typed

  select hq.q_kind, hq.q_blurt into r from public.host_question(g.host_token) hq;
  if r.q_kind <> 'text' or r.q_blurt then
    raise exception 'the typed question reports kind=% blurt=%', r.q_kind, r.q_blurt;
  end if;

  raise notice 'ok  each question opens in the phase it asked for; the opt-out cannot be claimed';
end $$;

do $$
declare g record; dev record; v_phase text; v_claimed boolean; r record;
begin
  -- The master switch wins over a question that wants a window.
  select * into g from public.create_game('33333333-3333-3333-3333-333333333333');
  perform public.update_game_settings(g.host_token, false);
  perform public.advance_game(g.host_token);
  select gg.phase into v_phase from public.games gg where gg.code = g.code;
  if v_phase <> 'question_open' then
    raise exception 'blurting is off for the whole game, yet q1 opened in %', v_phase;
  end if;

  -- With it on, question 1 still gets its window, and a claim takes the floor.
  select * into g from public.create_game('33333333-3333-3333-3333-333333333333');
  select * into dev from public.join_game(g.code, 'Dev');
  perform public.advance_game(g.host_token);
  v_claimed := public.blurt(dev.player_token);
  select gg.phase into v_phase from public.games gg where gg.code = g.code;
  if not v_claimed or v_phase <> 'blurt_claimed' then
    raise exception 'a claim on q1 gave claimed=% phase=%', v_claimed, v_phase;
  end if;

  raise notice 'ok  the master switch overrides a question; with it on, a claim takes the floor';
end $$;

do $$
declare v_copy uuid; r record; n int;
begin
  v_copy := public.duplicate_quiz('33333333-3333-3333-3333-333333333333');

  select count(*) into n from public.questions where quiz_id = v_copy;
  if n <> 3 then raise exception 'the copy has % questions, expected 3', n; end if;

  for r in select position, kind, blurt_enabled from public.questions
           where quiz_id = v_copy order by position loop
    if (r.position = 0) <> r.blurt_enabled then
      raise exception 'copied question % has blurt_enabled=%, expected %',
        r.position, r.blurt_enabled, (r.position = 0);
    end if;
  end loop;

  raise notice 'ok  duplicating a quiz keeps each question''s own blurt setting';
end $$;
