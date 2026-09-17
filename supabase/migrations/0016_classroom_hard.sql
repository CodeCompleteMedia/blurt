-- Phase 3: everything that breaks with thirty teenagers and never with three
-- phones on a desk.
--
-- Found by attacking the live database with nothing but the anon key:
--   * internal helpers were callable from a phone,
--   * one script could put seventy fake players in a room,
--   * and "Teacher", "Mr Patino" and worse were all accepted as names.

-- ------------------------------------------------------------ privileges ---

-- 0002 revoked execute "on all functions", which only ever meant the functions
-- that existed that day. Postgres grants every new function to PUBLIC, so each
-- helper added since has been callable by anyone. Close the ones that were never
-- meant to be an API, and flip the default so the next one starts closed.
revoke execute on function public.close_question_if_all_in(uuid) from public, anon, authenticated;
revoke execute on function public.question_limit_ms(public.games) from public, anon, authenticated;

alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- ----------------------------------------------------------------- schema ---

alter table public.games
  add column paused_at timestamptz,
  -- Extra time granted to the question on screen. Added to the limit rather than
  -- subtracted from the start: moving the start into the future would hand full
  -- marks to anyone answering before it "began", and every client treats a start
  -- in the future as a broken clock.
  add column extra_seconds int not null default 0 check (extra_seconds between 0 and 600);

-- Both belong to the question on screen and nothing else, so they clear whenever
-- the game moves on — here, once, rather than in every function that can move it.
create or replace function public.reset_question_state()
returns trigger
language plpgsql
as $$
begin
  if new.phase is distinct from old.phase or new.question_index is distinct from old.question_index then
    new.extra_seconds := 0;
    new.paused_at := null;
  end if;
  return new;
end;
$$;

create trigger games_reset_question_state
  before update on public.games
  for each row execute function public.reset_question_state();

-- ------------------------------------------------------------ name filter ---

-- No filter survives a determined fourteen-year-old; this one exists to stop the
-- lazy attempts, and kick + rename below are the real answer to the rest.
-- `anywhere` words match inside other text; the rest only as a whole word.
create table public.blocked_words (
  word text primary key,
  anywhere boolean not null default false
);

alter table public.blocked_words enable row level security;
revoke all on public.blocked_words from anon, authenticated;

insert into public.blocked_words (word, anywhere) values
  -- passing as the person in charge
  ('teacher', false), ('host', false), ('admin', false), ('moderator', false),
  ('blurt', false), ('mr', false), ('mrs', false), ('ms', false), ('miss', false),
  ('sir', false), ('prof', false), ('professor', false), ('principal', false),
  -- unambiguous wherever they appear, so disguises like "xXfuckXx" still trip
  ('fuck', true), ('bitch', true), ('cunt', true), ('nigg', true), ('fagg', true),
  ('whore', true), ('slut', true), ('penis', true), ('vagina', true),
  ('hitler', true), ('retard', true),
  -- only as a word of their own. Several of these sit inside real names —
  -- Shital, Nazir, Pornchai, Cassandra — and turning a student away from their
  -- own name is a worse failure than letting "bullshit" through to be removed.
  ('shit', false), ('rape', false), ('nazi', false), ('porn', false),
  ('ass', false), ('arse', false), ('dick', false), ('cock', false), ('tit', false),
  ('tits', false), ('fag', false), ('cum', false), ('sex', false), ('hoe', false),
  ('piss', false), ('wank', false), ('twat', false), ('kys', false);

create or replace function public.name_is_clean(p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_plain text;
  v_squashed text;
  v_tokens text[];
begin
  -- Undo the usual disguises: digits and symbols standing in for letters, then
  -- anything that is not a letter, then letters held down for emphasis.
  v_plain := lower(p_name);
  v_plain := translate(v_plain, '013457@$!|', 'oieastasii');
  v_plain := regexp_replace(v_plain, '[^a-z ]', '', 'g');
  v_plain := regexp_replace(v_plain, '(.)\1{2,}', '\1', 'g');
  v_squashed := replace(v_plain, ' ', '');
  v_tokens := regexp_split_to_array(trim(v_plain), '\s+');

  return not exists (
    select 1 from public.blocked_words b
    where (b.anywhere and position(b.word in v_squashed) > 0)
       or (not b.anywhere and b.word = any (v_tokens))
  );
end;
$$;

revoke execute on function public.name_is_clean(text) from public, anon, authenticated;

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
  v_count int;
  -- A class is forty at the outside. Past that it is a script, not a student.
  v_room_cap constant int := 60;
begin
  select * into v_game from public.games where code = upper(trim(p_code));
  if not found then
    raise exception 'no such room' using errcode = 'no_data_found';
  end if;

  if v_game.closed_at is not null then
    raise exception 'that room has closed' using errcode = 'check_violation';
  end if;

  if v_game.phase = 'final' then
    raise exception 'that game has finished' using errcode = 'check_violation';
  end if;

  if v_game.phase <> 'lobby' and not v_game.allow_late_join then
    raise exception 'that game has already started' using errcode = 'check_violation';
  end if;

  select count(*) into v_count from public.players where game_id = v_game.id;
  if v_count >= v_room_cap then
    raise exception 'that room is full' using errcode = 'check_violation';
  end if;

  -- Deliberately vague. Saying which word tripped it is a hint about what to
  -- try next.
  if not public.name_is_clean(p_name) then
    raise exception 'pick a different name' using errcode = 'check_violation';
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

-- -------------------------------------------------------------- reconnect ---

-- What a phone needs to put itself back exactly where it was after a refresh or
-- a lock screen: whether it has already answered this question, and whether it
-- is sitting one out. Correctness is not here — that waits for results like
-- everything else. It also doubles as the way a phone learns it has been removed:
-- a token that no longer resolves is a seat that no longer exists.
create or replace function public.my_seat(p_player_token uuid)
returns table (
  player_id uuid,
  player_name text,
  answered_current boolean,
  locked_out boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v_game public.games;
begin
  select p.* into v_player
  from public.players p
  join public.player_secrets s on s.player_id = p.id
  where s.token = p_player_token;

  if not found then
    raise exception 'not in this game' using errcode = 'no_data_found';
  end if;

  select * into v_game from public.games where id = v_player.game_id;

  return query
  select v_player.id,
         v_player.name,
         exists (
           select 1 from public.answers a
           where a.game_id = v_game.id and a.player_id = v_player.id
             and a.question_index = v_game.question_index and not a.blurted
         ),
         v_game.blurt_lockout and exists (
           select 1 from public.answers a
           where a.game_id = v_game.id and a.player_id = v_player.id
             and a.question_index = v_game.question_index and a.blurted and not a.correct
         );
end;
$$;

-- --------------------------------------------------------- kick and rename ---

create or replace function public.kick_player(p_host_token uuid, p_player_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_counted boolean;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token
  for update;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.players where id = p_player_id and game_id = v_game.id) then
    raise exception 'no such player' using errcode = 'no_data_found';
  end if;

  -- Were they already counted toward this question? Removing them must not leave
  -- the room one answer "ahead", or the question closes before the last real
  -- student has tapped.
  v_counted := exists (
    select 1 from public.answers a
    where a.game_id = v_game.id and a.player_id = p_player_id
      and a.question_index = v_game.question_index
      and (not a.blurted or (v_game.blurt_lockout and not a.correct))
  );

  delete from public.players where id = p_player_id;

  if v_game.phase = 'blurt_claimed' and v_game.blurted_by = p_player_id then
    -- They were holding the floor. Without this the game sits in a claim that
    -- nobody can judge.
    update public.games
    set phase = 'question_open', question_started_at = now(), blurted_by = null
    where id = v_game.id;
  elsif v_game.phase = 'question_open' then
    update public.games
    set answered_count = greatest(0, answered_count - (case when v_counted then 1 else 0 end))
    where id = v_game.id;
    -- Removing the one holdout should let the question finish.
    perform public.close_question_if_all_in(v_game.id);
  end if;
end;
$$;

-- The teacher's own choice of name is not filtered — they are the filter.
create or replace function public.rename_player(p_host_token uuid, p_player_id uuid, p_name text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game_id uuid;
begin
  select g.id into v_game_id
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token;

  if v_game_id is null then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  update public.players set name = trim(p_name)
  where id = p_player_id and game_id = v_game_id;

  if not found then
    raise exception 'no such player' using errcode = 'no_data_found';
  end if;
exception
  when unique_violation then
    raise exception 'someone in this room already has that name'
      using errcode = 'unique_violation';
end;
$$;

-- ------------------------------------------------------- pause and extend ---

create or replace function public.set_paused(p_host_token uuid, p_paused boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token
  for update;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  if p_paused then
    if v_game.phase not in ('recall', 'question_open') then
      raise exception 'nothing to pause' using errcode = 'check_violation';
    end if;
    update public.games set paused_at = now() where id = v_game.id and paused_at is null;
  else
    -- Hand back exactly the time that was taken away, so a fire drill costs
    -- nobody a point.
    update public.games
    set question_started_at = question_started_at + (now() - paused_at), paused_at = null
    where id = v_game.id and paused_at is not null;
  end if;
end;
$$;

create or replace function public.extend_question(p_host_token uuid, p_seconds int)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token
  for update;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  if v_game.phase not in ('recall', 'question_open') then
    raise exception 'no clock is running' using errcode = 'check_violation';
  end if;

  if p_seconds is null or p_seconds not between 5 and 120 then
    raise exception 'extend by 5 to 120 seconds' using errcode = 'check_violation';
  end if;

  update public.games set extra_seconds = least(600, extra_seconds + p_seconds)
  where id = v_game.id;
end;
$$;

-- The extension has to be part of the limit everywhere the limit is read, or the
-- screens and the deadline disagree — the same mistake as the recall override.
create or replace function public.question_limit_ms(p_game public.games)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (case
    when p_game.phase = 'recall'
      then coalesce(p_game.recall_seconds_override, q.recall_seconds)
    else coalesce(q.seconds, z.default_seconds)
  end + p_game.extra_seconds) * 1000
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = p_game.quiz_id
    and q.position = p_game.question_index;
$$;

revoke execute on function public.question_limit_ms(public.games) from public, anon, authenticated;

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
  select q.position,
         q.text,
         (case when v_game.phase in ('recall', 'blurt_claimed') then null else q.choices end),
         ((case
            when v_game.phase = 'recall'
              then coalesce(v_game.recall_seconds_override, q.recall_seconds)
            else coalesce(q.seconds, z.default_seconds)
          end) + v_game.extra_seconds)::int,
         (case when v_game.phase = 'results' then q.correct_index else null end)::int
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

create or replace function public.host_question(p_host_token uuid)
returns table (
  q_position int,
  q_text text,
  q_choices text[],
  q_seconds int,
  q_recall_seconds int,
  q_correct_index int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  if v_game.question_index < 0 then
    return;
  end if;

  return query
  select q.position,
         q.text,
         q.choices,
         (coalesce(q.seconds, z.default_seconds)
           + case when v_game.phase = 'recall' then 0 else v_game.extra_seconds end)::int,
         (coalesce(v_game.recall_seconds_override, q.recall_seconds)
           + case when v_game.phase = 'recall' then v_game.extra_seconds else 0 end)::int,
         q.correct_index
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

-- ------------------------------------------- nothing moves while paused ---

create or replace function public.blurt(p_player_token uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v_claimed int;
begin
  select p.* into v_player
  from public.players p
  join public.player_secrets s on s.player_id = p.id
  where s.token = p_player_token;

  if not found then
    raise exception 'not in this game' using errcode = 'no_data_found';
  end if;

  update public.games
  set phase = 'blurt_claimed', blurted_by = v_player.id
  where id = v_player.game_id
    and phase = 'recall'
    and blurt_enabled
    and paused_at is null
    and blurted_by is null;

  get diagnostics v_claimed = row_count;
  return v_claimed = 1;
end;
$$;

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
  v_correct boolean := false;
  v_awarded int := 0;
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

  if v_game.paused_at is not null then
    raise exception 'paused' using errcode = 'check_violation';
  end if;

  if v_game.blurt_lockout and exists (
    select 1 from public.answers a
    where a.game_id = v_game.id
      and a.player_id = v_player.id
      and a.question_index = v_game.question_index
      and a.blurted
      and not a.correct
  ) then
    return;
  end if;

  select * into v_question from public.questions
  where quiz_id = v_game.quiz_id and position = v_game.question_index;

  v_limit := public.question_limit_ms(v_game);
  v_elapsed := (extract(epoch from (now() - v_game.question_started_at)) * 1000)::int;

  if v_elapsed > v_limit + v_grace_ms then
    raise exception 'too late' using errcode = 'check_violation';
  end if;

  v_elapsed := greatest(0, least(v_elapsed, v_limit));
  v_correct := p_choice = v_question.correct_index;

  if v_correct then
    v_awarded := round(1000.0 * (v_limit - v_elapsed) / v_limit);
  end if;

  insert into public.answers
    (game_id, player_id, question_index, choice, ms_elapsed, awarded, correct)
  values (v_game.id, v_player.id, v_game.question_index, p_choice, v_elapsed, v_awarded, v_correct);

  update public.players set score = score + v_awarded where id = v_player.id;
  update public.games set answered_count = answered_count + 1 where id = v_game.id;

  perform public.close_question_if_all_in(v_game.id);
exception
  when unique_violation then
    return;
end;
$$;

-- ------------------------------------------------------------------ grants --

-- Defaults are closed now, so everything that *is* an API says so.
grant execute on function public.join_game(text, text) to anon, authenticated;
grant execute on function public.my_seat(uuid) to anon, authenticated;
grant execute on function public.kick_player(uuid, uuid) to anon, authenticated;
grant execute on function public.rename_player(uuid, uuid, text) to anon, authenticated;
grant execute on function public.set_paused(uuid, boolean) to anon, authenticated;
grant execute on function public.extend_question(uuid, int) to anon, authenticated;
grant execute on function public.current_question(text) to anon, authenticated;
grant execute on function public.host_question(uuid) to anon, authenticated;
grant execute on function public.blurt(uuid) to anon, authenticated;
grant execute on function public.submit_answer(uuid, int) to anon, authenticated;
