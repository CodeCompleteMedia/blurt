-- After the bell.
--
-- The point of this phase is one sentence: you should be able to see the two
-- questions the class bombed without opening a spreadsheet. So the report is not
-- a dump of the game — it is a list of questions ordered by how badly they went,
-- with enough beside each one to tell a bad question from a hard one.
--
-- Everything here is gated on owning the game, not on holding the host token: the
-- token lives in a browser and will be gone by the time anyone reads a report.

-- A game is worth reporting on once a question has been asked. Rooms opened and
-- abandoned in the lobby are noise, and there are always a few.
create or replace function public.my_games(p_limit int default 50)
returns table (
  game_id uuid,
  code text,
  played_at timestamptz,
  quiz_title text,
  finished boolean,
  players int,
  questions_asked int,
  questions_total int,
  top_name text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  return query
  select g.id,
         g.code,
         g.created_at,
         z.title,
         g.phase = 'final',
         (select count(*)::int from public.players p where p.game_id = g.id),
         (g.question_index + 1),
         (select count(*)::int from public.game_questions q where q.game_id = g.id),
         (select p.name from public.players p where p.game_id = g.id
          order by p.score desc, p.joined_at asc limit 1)
  from public.games g
  join public.quizzes z on z.id = g.quiz_id
  where g.owner_id = auth.uid() and g.question_index >= 0
  order by g.created_at desc
  limit greatest(1, least(p_limit, 200));
end;
$$;

grant execute on function public.my_games(int) to authenticated;

-- One row per question the class was actually asked, hardest first.
create or replace function public.game_report(p_game_id uuid)
returns table (
  q_position int,
  q_kind text,
  q_text text,
  q_answer text,
  answered int,
  correct int,
  percent_correct int,
  median_ms int,
  common_wrong text,
  common_wrong_count int,
  blurter text,
  blurt_correct boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select g.* into v_game from public.games g
  where g.id = p_game_id and g.owner_id = auth.uid();

  if not found then
    raise exception 'that is not your game' using errcode = 'insufficient_privilege';
  end if;

  return query
  with asked as (
    -- Only as far as the game actually got. A room abandoned at question three
    -- must not report questions four and five as nobody knowing them.
    select * from public.game_questions q
    where q.game_id = p_game_id and q.position <= v_game.question_index
  ),
  tallied as (
    select a.question_index,
           count(*) filter (where not a.blurted)::int as tapped,
           count(*) filter (where a.correct)::int as right_answers,
           percentile_cont(0.5) within group (order by a.ms_elapsed)
             filter (where not a.blurted) as median,
           count(*)::int as total
    from public.answers a
    where a.game_id = p_game_id
    group by a.question_index
  ),
  -- The wrong answer most of the room chose. On a bad question this is where they
  -- all went; on a hard one they scatter, and it stays small.
  wrong as (
    select distinct on (a.question_index)
           a.question_index,
           coalesce(a.answer_text, q.choices[a.choice + 1]) as label,
           count(*)::int as hits
    from public.answers a
    join asked q on q.position = a.question_index
    where not a.correct and not a.blurted
    group by a.question_index, coalesce(a.answer_text, q.choices[a.choice + 1])
    order by a.question_index, count(*) desc, 2
  )
  select q.position,
         q.kind,
         q.text,
         coalesce(q.accepted[1], q.choices[q.correct_index + 1]),
         coalesce(t.total, 0),
         coalesce(t.right_answers, 0),
         case when coalesce(t.total, 0) = 0 then 0
              else round(100.0 * t.right_answers / t.total)::int end,
         coalesce(t.median, 0)::int,
         w.label,
         w.hits,
         (select p.name from public.answers a
          join public.players p on p.id = a.player_id
          where a.game_id = p_game_id and a.question_index = q.position and a.blurted
          limit 1),
         (select a.correct from public.answers a
          where a.game_id = p_game_id and a.question_index = q.position and a.blurted
          limit 1)
  from asked q
  left join tallied t on t.question_index = q.position
  left join wrong w on w.question_index = q.position
  -- Hardest first: the whole point is not having to hunt for them.
  order by case when coalesce(t.total, 0) = 0 then 0
                else round(100.0 * t.right_answers / t.total) end asc,
           q.position asc;
end;
$$;

grant execute on function public.game_report(uuid) to authenticated;

-- One row per student, for the handful worth a conversation.
create or replace function public.game_players(p_game_id uuid)
returns table (
  player_id uuid,
  player_name text,
  score int,
  place int,
  answered int,
  correct int,
  best_streak int,
  blurt_wins int,
  blurt_misses int,
  avg_ms int,
  missed int[]
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select g.* into v_game from public.games g
  where g.id = p_game_id and g.owner_id = auth.uid();

  if not found then
    raise exception 'that is not your game' using errcode = 'insufficient_privilege';
  end if;

  return query
  with per_question as (
    select a.player_id, a.question_index,
           bool_or(a.correct) as correct,
           bool_or(a.blurted and a.correct) as blurt_win,
           bool_or(a.blurted and not a.correct) as blurt_miss,
           min(a.ms_elapsed) filter (where not a.blurted) as ms
    from public.answers a
    where a.game_id = p_game_id
    group by a.player_id, a.question_index
  ),
  -- Longest run of right answers: number each question, subtract a running count
  -- of the wrong ones, and every unbroken run shares a value to group on.
  -- Every column qualified: `player_id` is also an OUT parameter of this
  -- function, and an unqualified reference is ambiguous between the two.
  runs as (
    select pq.player_id, pq.question_index, pq.correct,
           pq.question_index - count(*) filter (where pq.correct)
             over (partition by pq.player_id order by pq.question_index) as run_id
    from per_question pq
  ),
  streaks as (
    select s.player_id, max(s.len)::int as best
    from (
      select r.player_id, r.run_id, count(*) as len
      from runs r where r.correct
      group by r.player_id, r.run_id
    ) s
    group by s.player_id
  ),
  agg as (
    select q.player_id,
           count(*)::int as answered,
           count(*) filter (where q.correct)::int as correct,
           count(*) filter (where q.blurt_win)::int as blurt_wins,
           count(*) filter (where q.blurt_miss)::int as blurt_misses,
           coalesce(avg(q.ms), 0)::int as avg_ms,
           coalesce(array_agg(q.question_index order by q.question_index)
                    filter (where not q.correct), '{}') as missed
    from per_question q
    group by q.player_id
  )
  select p.id, p.name, p.score,
         rank() over (order by p.score desc)::int,
         coalesce(a.answered, 0), coalesce(a.correct, 0),
         coalesce(s.best, 0), coalesce(a.blurt_wins, 0), coalesce(a.blurt_misses, 0),
         coalesce(a.avg_ms, 0), coalesce(a.missed, '{}')
  from public.players p
  left join agg a on a.player_id = p.id
  left join streaks s on s.player_id = p.id
  where p.game_id = p_game_id
  order by p.score desc, p.joined_at asc;
end;
$$;

grant execute on function public.game_players(uuid) to authenticated;

-- Enough to head a report: which quiz, when, how it ended.
create or replace function public.game_summary(p_game_id uuid)
returns table (
  code text,
  played_at timestamptz,
  quiz_title text,
  finished boolean,
  players int,
  questions_asked int,
  questions_total int,
  blurt_enabled boolean,
  streak_bonus boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  select g.code, g.created_at, z.title, g.phase = 'final',
         (select count(*)::int from public.players p where p.game_id = g.id),
         (g.question_index + 1),
         (select count(*)::int from public.game_questions q where q.game_id = g.id),
         g.blurt_enabled, g.streak_bonus
  from public.games g
  join public.quizzes z on z.id = g.quiz_id
  where g.id = p_game_id and g.owner_id = auth.uid();

  if not found then
    raise exception 'that is not your game' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

grant execute on function public.game_summary(uuid) to authenticated;

-- Deleting a game and everything recorded in it. A class may need a round
-- expunged, and "archive" is the wrong answer for a room someone was upset in.
create or replace function public.delete_game(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.games g where g.id = p_game_id and g.owner_id = auth.uid();
  if not found then
    raise exception 'that is not your game' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

grant execute on function public.delete_game(uuid) to authenticated;
