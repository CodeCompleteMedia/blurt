-- Settings, because several of these were never really answers.
--
-- The flow of a round has accumulated decisions that a teacher could reasonably
-- disagree with: whether a question everyone answered pauses before the reveal,
-- how long the recall window runs, whether blurting suits this class at all.
-- Those are preferences, and hardcoding a preference just means picking a side
-- for someone who is not in the room.
--
-- They live on the game rather than in the host's browser because the server acts
-- on them — the reveal pace is decided inside close_question_if_all_in, and the
-- shape of a round inside advance_game. A client-side setting could be edited by
-- anyone with the console, which for `blurt_enabled` would mean a student
-- deciding whether the class plays with the recall window.

alter table public.games
  add column blurt_enabled boolean not null default true,
  add column reveal_immediately boolean not null default true,
  -- 0 means wait for the teacher, which is why this is not nullable: null would
  -- be ambiguous with "leave this setting alone" in the patch below.
  add column auto_next_seconds int not null default 0
    check (auto_next_seconds between 0 and 30),
  add column recall_seconds_override int
    check (recall_seconds_override between 3 and 60);

-- Every argument is optional and null means "leave it". The host may change any
-- of these mid-game; they take effect from the next question.
create or replace function public.update_game_settings(
  p_host_token uuid,
  p_blurt_enabled boolean default null,
  p_reveal_immediately boolean default null,
  p_auto_next_seconds int default null,
  p_recall_seconds int default null,
  p_allow_late_join boolean default null
)
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

  update public.games
  set blurt_enabled = coalesce(p_blurt_enabled, blurt_enabled),
      reveal_immediately = coalesce(p_reveal_immediately, reveal_immediately),
      auto_next_seconds = coalesce(p_auto_next_seconds, auto_next_seconds),
      recall_seconds_override = coalesce(p_recall_seconds, recall_seconds_override),
      allow_late_join = coalesce(p_allow_late_join, allow_late_join)
  where id = v_game_id;
end;
$$;

-- The reveal pace is now the teacher's call.
create or replace function public.close_question_if_all_in(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_players int;
begin
  select * into v_game from public.games where id = p_game_id;
  if v_game.phase <> 'question_open' then
    return;
  end if;

  select count(*) into v_players from public.players where game_id = p_game_id;

  if v_players = 0 or v_game.answered_count < v_players then
    return;
  end if;

  -- Straight to the answer, or a beat on "All in" first. The other route into
  -- `locked` — the clock running out — is untouched either way, because there
  -- "Time" is telling the room why the question ended.
  update public.games
  set phase = case when v_game.reveal_immediately then 'results' else 'locked' end
  where id = p_game_id and phase = 'question_open';
end;
$$;

-- A game-wide recall window, overriding whatever each question carries.
create or replace function public.question_limit_ms(p_game public.games)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p_game.phase = 'recall'
      then coalesce(p_game.recall_seconds_override, q.recall_seconds) * 1000
    else coalesce(q.seconds, z.default_seconds) * 1000
  end
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = p_game.quiz_id
    and q.position = p_game.question_index;
$$;

-- With blurting off, a question simply opens with its choices up.
create or replace function public.advance_game(p_host_token uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_last int;
  v_opening text;
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
  v_opening := case when v_game.blurt_enabled then 'recall' else 'question_open' end;

  if v_game.phase = 'lobby' then
    update public.games set phase = v_opening, question_index = 0,
      question_started_at = now(), answered_count = 0, blurted_by = null
      where id = v_game.id;

  elsif v_game.phase = 'recall' then
    update public.games set phase = 'question_open', question_started_at = now()
      where id = v_game.id;

  elsif v_game.phase = 'blurt_claimed' then
    perform public.judge_blurt(p_host_token, false);

  elsif v_game.phase = 'question_open' then
    update public.games set phase = 'locked' where id = v_game.id;

  elsif v_game.phase = 'locked' then
    update public.games set phase = 'results' where id = v_game.id;

  elsif v_game.phase = 'results' then
    if v_game.question_index >= v_last then
      update public.games set phase = 'final', question_started_at = null
        where id = v_game.id;
    else
      update public.games set phase = v_opening,
        question_index = v_game.question_index + 1,
        question_started_at = now(), answered_count = 0, blurted_by = null
        where id = v_game.id;
    end if;
  end if;
end;
$$;

-- Defence in depth: with blurting off the phase never reaches `recall`, so this
-- cannot normally be called — but the setting is a rule, and rules belong where
-- they cannot be reached around.
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
    and blurted_by is null;

  get diagnostics v_claimed = row_count;
  return v_claimed = 1;
end;
$$;

grant execute on function public.update_game_settings(uuid, boolean, boolean, int, int, boolean)
  to anon, authenticated;
