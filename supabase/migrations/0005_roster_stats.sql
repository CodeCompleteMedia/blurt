-- What the teacher's screen is for.
--
-- `answers` is unreadable by anon and stays that way, so the per-student view
-- comes through a function gated on the host token. The projector never calls
-- this; it is the difference between the two surfaces.

-- Correctness was inferred from `awarded > 0`, which quietly misreads a correct
-- answer landing on the deadline for exactly zero points. Record it instead.
alter table public.answers add column correct boolean not null default false;
update public.answers set correct = (awarded > 0);

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
exception
  when unique_violation then
    -- Already answered, or locked out by a wrong blurt. Either way their tap
    -- does nothing, silently — a double tap is not an error worth putting on a
    -- teenager's screen.
    return;
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
          case when p_correct then v_award else 0 end, p_correct)
  on conflict do nothing;

  if p_correct then
    update public.players set score = score + v_award where id = v_game.blurted_by;
    update public.games set phase = 'results', answered_count = answered_count + 1
      where id = v_game.id;
  else
    update public.games
    set phase = 'question_open', question_started_at = now(), answered_count = answered_count + 1
      where id = v_game.id;
  end if;
end;
$$;

-- The roster, as a teacher needs to read it mid-lesson: not a scoreboard, but
-- who is keeping up and who has gone quiet.
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
  with ranked as (
    select a.player_id, a.question_index, a.correct, a.blurted, a.ms_elapsed, a.awarded,
           row_number() over (partition by a.player_id order by a.question_index desc) as recency
    from public.answers a
    where a.game_id = v_game.id
  ),
  agg as (
    select r.player_id,
           count(*)::int as answered,
           count(*) filter (where r.correct)::int as correct,
           -- Leading run of correct answers, counting back from the most recent.
           coalesce(min(r.recency) filter (where not r.correct) - 1, count(*))::int as streak,
           coalesce(avg(r.ms_elapsed) filter (where not r.blurted), 0)::int as avg_ms,
           count(*) filter (where r.blurted and r.correct)::int as blurt_wins,
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
         ),
         -- How many questions since they last answered anything. This is the
         -- column that finds the phone that went face-down.
         greatest(0, v_game.question_index - coalesce(a.last_question, -1))::int
  from public.players p
  left join agg a on a.player_id = p.id
  where p.game_id = v_game.id
  order by p.score desc, p.joined_at asc;
end;
$$;

grant execute on function public.roster_stats(uuid) to anon, authenticated;
