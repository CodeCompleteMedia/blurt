-- Knowing the room code becomes the only way into a room.
--
-- `games` and `players` were readable by anyone holding the anon key, which
-- ships in the browser bundle. Verified against a two-teacher database: that
-- read every room code in the schema and every student's name and score in
-- every teacher's game. The answer key was never exposed — `answers`, both
-- secrets tables, `questions` and the `game_questions` snapshot were always
-- refused — but a roster is not public information either.
--
-- The policies said `using (true)` because Realtime's postgres_changes only
-- delivers rows the subscriber may select, so tightening them would have gone
-- unnoticed until the projector stopped advancing. 0028 moves that subscription
-- to Broadcast, which is what makes this possible.

-- The public-safe view of a room, keyed by the code. Everything the wall and a
-- phone need, and nothing that says whose room it is.
create or replace function public.game_state(p_code text)
returns table (
  id uuid,
  code text,
  quiz_id uuid,
  phase text,
  question_index int,
  question_started_at timestamptz,
  answered_count int,
  allow_late_join boolean,
  created_at timestamptz,
  blurted_by uuid,
  closed_at timestamptz,
  blurt_enabled boolean,
  reveal_immediately boolean,
  auto_next_seconds int,
  recall_seconds_override int,
  blurt_lockout boolean,
  blurt_penalty int,
  paused_at timestamptz,
  extra_seconds int,
  streak_bonus boolean
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select g.id, g.code, g.quiz_id, g.phase, g.question_index, g.question_started_at,
         g.answered_count, g.allow_late_join, g.created_at, g.blurted_by, g.closed_at,
         g.blurt_enabled, g.reveal_immediately, g.auto_next_seconds,
         g.recall_seconds_override, g.blurt_lockout, g.blurt_penalty, g.paused_at,
         g.extra_seconds, g.streak_bonus
  from public.games g
  where g.code = upper(trim(p_code));
$$;

grant execute on function public.game_state(text) to anon, authenticated;

-- The roster, keyed by the same code rather than by the game id, so there is one
-- secret per room instead of two.
create or replace function public.roster(p_code text)
returns table (id uuid, name text, score int)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id, p.name, p.score
  from public.players p
  join public.games g on g.id = p.game_id
  where g.code = upper(trim(p_code))
  order by p.score desc, p.joined_at asc;
$$;

grant execute on function public.roster(text) to anon, authenticated;

-- With both reads served by function, the tables themselves can close.
drop policy if exists games_readable on public.games;
drop policy if exists players_readable on public.players;
revoke select on public.games, public.players from anon, authenticated;

-- And they no longer need to be in the postgres_changes publication: nothing is
-- allowed to select them, so it could deliver nothing anyway.
alter publication supabase_realtime drop table public.games;
alter publication supabase_realtime drop table public.players;
