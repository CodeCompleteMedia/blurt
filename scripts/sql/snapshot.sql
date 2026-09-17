-- A room is asked the questions it opened with, whatever happens to the quiz.
--
-- Without this, editing a quiz would rewrite history: a report would show
-- questions the class was never asked, and a mid-lesson typo fix could change
-- which answer counted as correct while the question was on screen.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select public.copy_sample_quiz() as quiz \gset
select code, host_token from public.create_game(:'quiz') \gset
select player_id, player_token from public.join_game(:'code', 'Rosa') \gset r_
select set_config('blurt.quiz', :'quiz', false) \gset x
select set_config('blurt.code', :'code', false) \gset x
select set_config('blurt.host', :'host_token', false) \gset x
select set_config('blurt.rosa', :'r_player_token', false) \gset x
select public.update_game_settings(:'host_token', false) \gset x
select public.advance_game(:'host_token') \gset x

do $$
declare
  -- Every local is v_-prefixed: `code` and `position` are column names here,
  -- and plpgsql resolves the variable first, silently.
  v_quiz uuid := current_setting('blurt.quiz')::uuid;
  v_code text := current_setting('blurt.code');
  v_host uuid := current_setting('blurt.host')::uuid;
  v_gid uuid := (select g.id from public.games g where g.code = current_setting('blurt.code'));
  v_opened_with text;
  n int;
  r record;
begin
  select count(*) into n from public.game_questions where game_id = v_gid;
  if n <> 5 then raise exception 'the game copied % questions, expected 5', n; end if;

  select cq.q_text into v_opened_with from public.current_question(v_code) cq;

  -- The teacher edits the live quiz mid-lesson: rewrites question one, moves
  -- its correct answer, and deletes the last two questions.
  update public.questions set text = 'REWRITTEN', correct_index = 3
  where quiz_id = v_quiz and position = 0;
  delete from public.questions where quiz_id = v_quiz and position in (3, 4);

  select * into r from public.current_question(v_code);
  if r.q_text = 'REWRITTEN' then
    raise exception 'the question on screen changed under the class mid-question';
  end if;
  if r.q_text <> v_opened_with then
    raise exception 'the question on screen changed from "%" to "%"', v_opened_with, r.q_text;
  end if;

  -- And the answer that was correct when the class was shown it still is.
  perform public.submit_answer(current_setting('blurt.rosa')::uuid, 1);
  if not (select a.correct from public.answers a where a.game_id = v_gid) then
    raise exception 'the edit changed which answer counted, mid-question';
  end if;

  -- Deleting two questions must not end the lesson early.
  perform public.advance_game(v_host) from generate_series(1, 25);
  select g.phase, g.question_index into r from public.games g where g.id = v_gid;
  if r.phase <> 'final' or r.question_index <> 4 then
    raise exception 'game ended at phase % question %, expected final on question 4',
      r.phase, r.question_index;
  end if;

  raise notice 'ok  a running room keeps the five questions it opened with';
end $$;

-- A room opened afterwards gets the quiz as it is now, or the snapshot would be
-- a freeze rather than a copy.
select code as c2, host_token as h2 from public.create_game(:'quiz') \gset
select set_config('blurt.c2', :'c2', false) \gset x
select public.advance_game(:'h2') \gset x
select public.advance_game(:'h2') \gset x

do $$
declare n int; t text;
begin
  select count(*) into n from public.game_questions
  where game_id = (select id from public.games where code = current_setting('blurt.c2'));
  if n <> 3 then raise exception 'the new room copied % questions, expected 3', n; end if;

  select q_text into t from public.current_question(current_setting('blurt.c2'));
  if t <> 'REWRITTEN' then
    raise exception 'the new room shows "%", expected the edited text', t;
  end if;
  raise notice 'ok  a room opened after the edit gets the edit';
end $$;

-- The copy holds every correct answer for the whole game, so it must be no more
-- readable than the questions it came from.
do $$
declare
  n int;
  who text;
begin
  -- Either outcome is fine — no SELECT grant at all, or a grant that RLS
  -- filters to nothing. What must never happen is rows coming back.
  foreach who in array array['anon', 'authenticated'] loop
    begin
      execute format('set local role %I', who);
      execute 'select count(*) from public.game_questions' into n;
      execute 'reset role';
      if n <> 0 then
        raise exception '% can read % rows of game_questions', who, n;
      end if;
    exception when insufficient_privilege then
      execute 'reset role';
    end;
  end loop;

  raise notice 'ok  the answer key copy is refused to anon and authenticated alike';
end $$;
