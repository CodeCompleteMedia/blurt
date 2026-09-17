-- Streaks: a run of right answers is worth a little more each time.
--
-- A bonus is a scoring rule, so it lives here with the others rather than being
-- dressed up on a screen — and it is a setting, because whether a class should be
-- rewarded for momentum is the teacher's call.
--
-- A run is consecutive *questions*, not consecutive answers. Skipping a question
-- breaks it; otherwise the way to protect a streak would be to stop answering.

alter table public.games add column streak_bonus boolean not null default true;

-- Kept apart from `awarded` so a phone can say "+961, and +200 for the run"
-- instead of showing one number nobody can account for.
alter table public.answers add column bonus int not null default 0;

-- How many questions in a row this player had right going into question p_index.
create or replace function public.streak_before(p_game_id uuid, p_player_id uuid, p_index int)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  -- Find the most recent earlier question they did NOT get right — answered wrong,
  -- or not answered at all — and count forward from there.
  select p_index - 1 - coalesce(max(i), -1)
  from generate_series(0, p_index - 1) as i
  where not exists (
    select 1 from public.answers a
    where a.game_id = p_game_id and a.player_id = p_player_id
      and a.question_index = i and a.correct
  );
$$;

revoke execute on function public.streak_before(uuid, uuid, int) from public, anon, authenticated;

-- A hundred a question, from the second in a row, capped so a long quiz does not
-- turn into a contest nobody else can catch.
create or replace function public.streak_points(p_game public.games, p_player_id uuid)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p_game.streak_bonus
      then least(public.streak_before(p_game.id, p_player_id, p_game.question_index), 5) * 100
    else 0
  end;
$$;

revoke execute on function public.streak_points(public.games, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------- answers ---

create or replace function public.record_answer(p_player_token uuid, p_choice int, p_text text)
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
  v_bonus int := 0;
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
    where a.game_id = v_game.id and a.player_id = v_player.id
      and a.question_index = v_game.question_index and a.blurted and not a.correct
  ) then
    return;
  end if;

  select * into v_question from public.questions
  where quiz_id = v_game.quiz_id and position = v_game.question_index;

  if v_question.kind = 'text' then
    if p_text is null or char_length(trim(p_text)) = 0 then
      raise exception 'type an answer' using errcode = 'check_violation';
    end if;
    v_correct := public.answer_key(p_text) in (
      select public.answer_key(a) from unnest(v_question.accepted) as a
    );
  else
    if p_choice is null or p_choice not between 0 and array_length(v_question.choices, 1) - 1 then
      raise exception 'not one of the choices' using errcode = 'check_violation';
    end if;
    v_correct := p_choice = v_question.correct_index;
  end if;

  v_limit := public.question_limit_ms(v_game);
  v_elapsed := (extract(epoch from (now() - v_game.question_started_at)) * 1000)::int;

  if v_elapsed > v_limit + v_grace_ms then
    raise exception 'too late' using errcode = 'check_violation';
  end if;

  v_elapsed := greatest(0, least(v_elapsed, v_limit));
  if v_correct then
    v_awarded := round(1000.0 * (v_limit - v_elapsed) / v_limit);
    v_bonus := public.streak_points(v_game, v_player.id);
  end if;

  insert into public.answers
    (game_id, player_id, question_index, choice, answer_text, ms_elapsed, awarded, bonus, correct)
  values (
    v_game.id, v_player.id, v_game.question_index,
    case when v_question.kind = 'text' then null else p_choice end,
    case when v_question.kind = 'text' then left(trim(p_text), 80) else null end,
    v_elapsed, v_awarded, v_bonus, v_correct
  );

  update public.players set score = score + v_awarded + v_bonus where id = v_player.id;
  update public.games set answered_count = answered_count + 1 where id = v_game.id;

  perform public.close_question_if_all_in(v_game.id);
exception
  when unique_violation then
    return;
end;
$$;

revoke execute on function public.record_answer(uuid, int, text) from public, anon, authenticated;

-- A blurt carries a run forward like any other right answer.
create or replace function public.judge_blurt(p_host_token uuid, p_correct boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_award constant int := 1500;
  v_bonus int := 0;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token
  for update;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  if v_game.phase <> 'blurt_claimed' or v_game.blurted_by is null then
    raise exception 'nobody is blurting' using errcode = 'check_violation';
  end if;

  if p_correct then
    v_bonus := public.streak_points(v_game, v_game.blurted_by);
  end if;

  insert into public.answers
    (game_id, player_id, question_index, choice, blurted, ms_elapsed, awarded, bonus, correct)
  values (v_game.id, v_game.blurted_by, v_game.question_index, null, true, 0,
          case when p_correct then v_award else -v_game.blurt_penalty end, v_bonus, p_correct)
  on conflict do nothing;

  if p_correct then
    update public.players set score = score + v_award + v_bonus where id = v_game.blurted_by;
    update public.games set phase = 'results', answered_count = answered_count + 1
      where id = v_game.id;
  else
    update public.players
    set score = greatest(0, score - v_game.blurt_penalty)
    where id = v_game.blurted_by;

    update public.games
    set phase = 'question_open',
        question_started_at = now(),
        answered_count = answered_count + (case when v_game.blurt_lockout then 1 else 0 end)
    where id = v_game.id;

    perform public.close_question_if_all_in(v_game.id);
  end if;
end;
$$;

-- ------------------------------------------------------------- own result ---

-- Gains a column, so it is a drop rather than a replace.
drop function public.my_result(uuid);

create function public.my_result(p_player_token uuid)
returns table (
  answered boolean,
  correct boolean,
  awarded int,
  bonus int,
  blurted boolean,
  streak int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v_game public.games;
  v_right boolean;
begin
  select p.* into v_player
  from public.players p
  join public.player_secrets s on s.player_id = p.id
  where s.token = p_player_token;

  if not found then
    raise exception 'not in this game' using errcode = 'no_data_found';
  end if;

  select * into v_game from public.games where id = v_player.game_id;

  if v_game.phase not in ('results', 'final') then
    return;
  end if;

  v_right := exists (
    select 1 from public.answers a
    where a.game_id = v_game.id and a.player_id = v_player.id
      and a.question_index = v_game.question_index and a.correct
  );

  return query
  select
    exists (select 1 from public.answers a
            where a.game_id = v_game.id and a.player_id = v_player.id
              and a.question_index = v_game.question_index),
    v_right,
    coalesce((select sum(greatest(a.awarded, 0))::int from public.answers a
              where a.game_id = v_game.id and a.player_id = v_player.id
                and a.question_index = v_game.question_index), 0),
    coalesce((select sum(a.bonus)::int from public.answers a
              where a.game_id = v_game.id and a.player_id = v_player.id
                and a.question_index = v_game.question_index), 0),
    exists (select 1 from public.answers a
            where a.game_id = v_game.id and a.player_id = v_player.id
              and a.question_index = v_game.question_index and a.blurted),
    -- The run as it stands now: one longer if this was right, gone if it was not.
    case when v_right
      then public.streak_before(v_game.id, v_player.id, v_game.question_index) + 1
      else 0
    end;
end;
$$;

grant execute on function public.my_result(uuid) to anon, authenticated;

-- ---------------------------------------------------------------- settings ---

-- One more argument means a new signature, and `create or replace` would leave the
-- eight-argument version standing beside this one — which is how every settings
-- change quietly broke once before. Drop it first.
drop function public.update_game_settings(uuid, boolean, boolean, int, int, boolean, boolean, int);

create function public.update_game_settings(
  p_host_token uuid,
  p_blurt_enabled boolean default null,
  p_reveal_immediately boolean default null,
  p_auto_next_seconds int default null,
  p_recall_seconds int default null,
  p_allow_late_join boolean default null,
  p_blurt_lockout boolean default null,
  p_blurt_penalty int default null,
  p_streak_bonus boolean default null
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
      allow_late_join = coalesce(p_allow_late_join, allow_late_join),
      blurt_lockout = coalesce(p_blurt_lockout, blurt_lockout),
      blurt_penalty = coalesce(p_blurt_penalty, blurt_penalty),
      streak_bonus = coalesce(p_streak_bonus, streak_bonus)
  where id = v_game_id;
end;
$$;

grant execute on function public.update_game_settings(uuid, boolean, boolean, int, int, boolean, boolean, int, boolean)
  to anon, authenticated;
