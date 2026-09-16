-- Every rule in blurt lives here. These are the only way a client changes
-- anything, and the only way a client learns a correct answer.
--
-- Each function is SECURITY DEFINER with a pinned search_path, so it runs with
-- the owner's rights regardless of who calls it, and cannot be hijacked by a
-- caller-controlled schema.

-- --------------------------------------------------------------- helpers ---

create or replace function public.question_limit_ms(p_game public.games)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(q.seconds, z.default_seconds) * 1000
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = p_game.quiz_id
    and q.position = p_game.question_index;
$$;

-- ------------------------------------------------------------ create game ---

create or replace function public.create_game(p_quiz_id uuid)
returns table (code text, host_token uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
  v_game public.games;
  v_host_token uuid;
begin
  -- Ambiguity-free alphabet: no O/0, no I/1, so a code read from the back of
  -- the room is never typed wrong.
  loop
    v_code := (
      select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                               (random() * 31)::int + 1, 1), '')
      from generate_series(1, 5)
    );
    exit when not exists (select 1 from public.games g where g.code = v_code);
  end loop;

  insert into public.games (code, quiz_id) values (v_code, p_quiz_id)
  returning * into v_game;

  insert into public.game_secrets (game_id) values (v_game.id)
  returning game_secrets.host_token into v_host_token;

  return query select v_game.code, v_host_token;
end;
$$;

-- -------------------------------------------------------------- join game ---

create or replace function public.join_game(p_code text, p_name text)
returns table (player_id uuid, player_token uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_player public.players;
  v_token uuid;
begin
  select * into v_game from public.games where code = upper(trim(p_code));
  if not found then
    raise exception 'no such room' using errcode = 'no_data_found';
  end if;

  if v_game.phase = 'final' then
    raise exception 'that game has finished' using errcode = 'check_violation';
  end if;

  if v_game.phase <> 'lobby' and not v_game.allow_late_join then
    raise exception 'that game has already started' using errcode = 'check_violation';
  end if;

  insert into public.players (game_id, name) values (v_game.id, trim(p_name))
  returning * into v_player;

  insert into public.player_secrets (player_id) values (v_player.id)
  returning player_secrets.token into v_token;

  return query select v_player.id, v_token;
exception
  when unique_violation then
    raise exception 'someone in this room already has that name'
      using errcode = 'unique_violation';
end;
$$;

-- ----------------------------------------------------------- submit answer ---

-- Takes a seat token and a choice. Nothing else — not the time taken, not the
-- score, not the player id. Those are the three things a client would lie about,
-- so all three are derived here from the server clock and the stored row.
create or replace function public.submit_answer(p_player_token uuid, p_choice int)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v_game public.games;
  v_question public.questions;
  v_limit int;
  v_elapsed int;
  v_awarded int := 0;
  -- Enough slack for a phone on school wifi, not enough to be worth gaming.
  v_grace_ms constant int := 750;
begin
  select p.* into v_player
  from public.players p
  join public.player_secrets s on s.player_id = p.id
  where s.token = p_player_token;

  if not found then
    raise exception 'not in this game' using errcode = 'no_data_found';
  end if;

  select * into v_game from public.games where id = v_player.game_id for update;

  if v_game.phase <> 'question_open' then
    raise exception 'not taking answers' using errcode = 'check_violation';
  end if;

  select * into v_question from public.questions
  where quiz_id = v_game.quiz_id and position = v_game.question_index;

  v_limit := public.question_limit_ms(v_game);
  v_elapsed := (extract(epoch from (now() - v_game.question_started_at)) * 1000)::int;

  if v_elapsed > v_limit + v_grace_ms then
    raise exception 'too late' using errcode = 'check_violation';
  end if;

  -- Clamp inside the window so the grace period cannot buy points.
  v_elapsed := greatest(0, least(v_elapsed, v_limit));

  if p_choice = v_question.correct_index then
    v_awarded := round(1000.0 * (v_limit - v_elapsed) / v_limit);
  end if;

  insert into public.answers (game_id, player_id, question_index, choice, ms_elapsed, awarded)
  values (v_game.id, v_player.id, v_game.question_index, p_choice, v_elapsed, v_awarded);

  update public.players set score = score + v_awarded where id = v_player.id;
  update public.games set answered_count = answered_count + 1 where id = v_game.id;
exception
  when unique_violation then
    -- Already answered. Silent, because a double tap is not an error worth
    -- putting on a teenager's screen.
    return;
end;
$$;

-- ---------------------------------------------------------------- advance ---

-- The teacher's spacebar. Mirrors src/lib/game.js exactly, but here it is the
-- authority: the client copy only predicts what this will do.
create or replace function public.advance_game(p_host_token uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_last int;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token
  for update;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  select max(q.position) into v_last from public.questions q where q.quiz_id = v_game.quiz_id;

  if v_game.phase = 'lobby' then
    update public.games set phase = 'question_open', question_index = 0,
      question_started_at = now(), answered_count = 0 where id = v_game.id;

  elsif v_game.phase = 'question_open' then
    update public.games set phase = 'locked' where id = v_game.id;

  elsif v_game.phase = 'locked' then
    update public.games set phase = 'results' where id = v_game.id;

  elsif v_game.phase = 'results' then
    if v_game.question_index >= v_last then
      update public.games set phase = 'final', question_started_at = null
        where id = v_game.id;
    else
      update public.games set phase = 'question_open',
        question_index = v_game.question_index + 1,
        question_started_at = now(), answered_count = 0 where id = v_game.id;
    end if;
  end if;
end;
$$;

-- ------------------------------------------------------------------ reads ---

-- The current question, with the correct answer withheld until the projector
-- has revealed it. This is a function rather than a view because the withholding
-- has to be a condition the client cannot rewrite.
create or replace function public.current_question(p_code text)
returns table (q_position int, q_text text, q_choices text[], q_seconds int, q_correct_index int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select * into v_game from public.games g where g.code = upper(trim(p_code));
  if not found or v_game.question_index < 0 then
    return;
  end if;

  return query
  select q.position, q.text, q.choices,
         coalesce(q.seconds, z.default_seconds)::int,
         (case when v_game.phase = 'results' then q.correct_index else null end)::int
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

-- What the class picked. Empty until results, so nobody can watch the vote come
-- in and follow the crowd.
create or replace function public.distribution(p_code text)
returns table (answer_choice int, answer_count bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select * into v_game from public.games g where g.code = upper(trim(p_code));
  if not found or v_game.phase <> 'results' then
    return;
  end if;

  return query
  select c.choice, count(a.id)
  from generate_series(0, 3) as c(choice)
  left join public.answers a
    on a.choice = c.choice
   and a.game_id = v_game.id
   and a.question_index = v_game.question_index
  group by c.choice
  order by c.choice;
end;
$$;

-- ------------------------------------------------------------------ grants --

revoke execute on all functions in schema public from anon, authenticated;

grant execute on function public.join_game(text, text) to anon, authenticated;
grant execute on function public.submit_answer(uuid, int) to anon, authenticated;
grant execute on function public.advance_game(uuid) to anon, authenticated;
grant execute on function public.create_game(uuid) to anon, authenticated;
grant execute on function public.current_question(text) to anon, authenticated;
grant execute on function public.distribution(text) to anon, authenticated;
