-- What a wrong blurt costs, as a setting.
--
-- Two things, because they are genuinely separate: whether you lose your shot at
-- the question, and whether it costs you points. A class that needs blurting
-- encouraged and one that needs it discouraged want different answers.
--
-- The lockout stops being emergent. Until now a wrong blurt wrote an answers row
-- and the unique index refused the tapped answer that followed — elegant, but it
-- means "no lockout" cannot be expressed without throwing away the record of the
-- blurt entirely, and a later phase wants to report on who risked it and how it
-- went. So a blurt and a tapped answer become separate rows, and the lockout
-- becomes a rule stated where rules live.

alter table public.games
  add column blurt_lockout boolean not null default true,
  add column blurt_penalty int not null default 0 check (blurt_penalty between 0 and 1000);

-- One blurt and one tapped answer per player per question, rather than one row
-- of either kind.
-- The constraint owns the index, so it has to go first; the bare index drop is
-- only a safety net for a database where it exists without one.
alter table public.answers drop constraint if exists answers_game_id_player_id_question_index_key;
drop index if exists public.answers_game_id_player_id_question_index_key;
create unique index answers_one_of_each
  on public.answers (game_id, player_id, question_index, blurted);

create or replace function public.update_game_settings(
  p_host_token uuid,
  p_blurt_enabled boolean default null,
  p_reveal_immediately boolean default null,
  p_auto_next_seconds int default null,
  p_recall_seconds int default null,
  p_allow_late_join boolean default null,
  p_blurt_lockout boolean default null,
  p_blurt_penalty int default null
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
      blurt_penalty = coalesce(p_blurt_penalty, blurt_penalty)
  where id = v_game_id;
end;
$$;

create or replace function public.judge_blurt(p_host_token uuid, p_correct boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_award constant int := 1500;
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

  insert into public.answers
    (game_id, player_id, question_index, choice, blurted, ms_elapsed, awarded, correct)
  values (v_game.id, v_game.blurted_by, v_game.question_index, null, true, 0,
          case when p_correct then v_award else -v_game.blurt_penalty end, p_correct)
  on conflict do nothing;

  if p_correct then
    update public.players set score = score + v_award where id = v_game.blurted_by;
    update public.games set phase = 'results', answered_count = answered_count + 1
      where id = v_game.id;
  else
    -- Floored at zero. A scoreboard that goes negative lands badly in a room of
    -- teenagers, and the point of the penalty is to make blurting a decision, not
    -- to bury anyone.
    update public.players
    set score = greatest(0, score - v_game.blurt_penalty)
    where id = v_game.blurted_by;

    update public.games
    set phase = 'question_open',
        question_started_at = now(),
        -- Only count them as done if they are actually out. Without the lockout
        -- they still owe an answer, and counting them would close the question
        -- while the room was still waiting on them.
        answered_count = answered_count + (case when v_game.blurt_lockout then 1 else 0 end)
    where id = v_game.id;

    perform public.close_question_if_all_in(v_game.id);
  end if;
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

  -- The lockout, said out loud. It used to be the unique index refusing a second
  -- row, which worked only because there was no way to switch it off.
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

-- A player can now have two rows for one question, so anything that reads them
-- has to roll up per question first or it will double-count.
create or replace function public.my_result(p_player_token uuid)
returns table (
  answered boolean,
  correct boolean,
  awarded int,
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

  return query
  with per_question as (
    select a.question_index,
           bool_or(a.correct) as correct,
           sum(a.awarded)::int as awarded,
           bool_or(a.blurted) as blurted
    from public.answers a
    where a.game_id = v_game.id and a.player_id = v_player.id
    group by a.question_index
  ),
  ranked as (
    select *, row_number() over (order by question_index desc) as recency from per_question
  ),
  this_one as (
    select * from per_question where question_index = v_game.question_index
  )
  select
    exists (select 1 from this_one),
    coalesce((select t.correct from this_one t), false),
    coalesce((select t.awarded from this_one t), 0),
    coalesce((select t.blurted from this_one t), false),
    coalesce(
      (select (min(r.recency) filter (where not r.correct) - 1)::int from ranked r),
      (select count(*)::int from ranked)
    );
end;
$$;

create or replace function public.roster_stats(p_host_token uuid)
returns table (
  player_id uuid,
  player_name text,
  score int,
  answered int,
  correct int,
  streak int,
  avg_ms int,
  blurt_wins int,
  answered_current boolean,
  quiet_for int
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

  return query
  with per_question as (
    select a.player_id,
           a.question_index,
           bool_or(a.correct) as correct,
           bool_or(a.blurted and a.correct) as blurt_win,
           min(a.ms_elapsed) filter (where not a.blurted) as ms
    from public.answers a
    where a.game_id = v_game.id
    group by a.player_id, a.question_index
  ),
  ranked as (
    select q.*,
           row_number() over (partition by q.player_id order by q.question_index desc) as recency
    from per_question q
  ),
  agg as (
    select r.player_id,
           count(*)::int as answered,
           count(*) filter (where r.correct)::int as correct,
           coalesce(min(r.recency) filter (where not r.correct) - 1, count(*))::int as streak,
           coalesce(avg(r.ms), 0)::int as avg_ms,
           count(*) filter (where r.blurt_win)::int as blurt_wins,
           max(r.question_index)::int as last_question
    from ranked r
    group by r.player_id
  )
  select p.id,
         p.name,
         p.score,
         coalesce(a.answered, 0),
         coalesce(a.correct, 0),
         coalesce(a.streak, 0),
         coalesce(a.avg_ms, 0),
         coalesce(a.blurt_wins, 0),
         exists (
           select 1 from public.answers x
           where x.game_id = v_game.id
             and x.player_id = p.id
             and x.question_index = v_game.question_index
             and (not x.blurted or v_game.blurt_lockout or x.correct)
         ),
         greatest(0, v_game.question_index - coalesce(a.last_question, -1))::int
  from public.players p
  left join agg a on a.player_id = p.id
  where p.game_id = v_game.id
  order by p.score desc, p.joined_at asc;
end;
$$;

grant execute on function public.update_game_settings(uuid, boolean, boolean, int, int, boolean, boolean, int)
  to anon, authenticated;
