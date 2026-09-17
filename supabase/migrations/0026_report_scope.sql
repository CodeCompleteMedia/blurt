-- The most-common-miss was counted across every game ever played.
--
-- `game_report` built that column from a join on question *position* and forgot to
-- filter by game, so "the wrong answer most of this room chose" was really the
-- wrong answer most of everybody had ever chosen at that position — across other
-- teachers' games too. The counts were the giveaway: one student, thirty-eight
-- wrong answers.
--
-- It passed every test because the test database held exactly one game per
-- question position. The check added alongside this plays two games, so the
-- missing filter cannot come back unnoticed.

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
    select * from public.game_questions q
    where q.game_id = p_game_id and q.position <= v_game.question_index
  ),
  mine as (
    -- Every later clause reads from here rather than from `answers`, so there is
    -- one place the game is filtered instead of three places to forget it.
    select a.* from public.answers a where a.game_id = p_game_id
  ),
  tallied as (
    select a.question_index,
           count(*) filter (where a.correct)::int as right_answers,
           percentile_cont(0.5) within group (order by a.ms_elapsed)
             filter (where not a.blurted) as median,
           count(*)::int as total
    from mine a
    group by a.question_index
  ),
  wrong as (
    select distinct on (a.question_index)
           a.question_index,
           coalesce(a.answer_text, q.choices[a.choice + 1]) as label,
           count(*)::int as hits
    from mine a
    join asked q on q.position = a.question_index
    where not a.correct and not a.blurted
    group by a.question_index, coalesce(a.answer_text, q.choices[a.choice + 1])
    order by a.question_index, count(*) desc, 2
  ),
  claimed as (
    select distinct on (a.question_index) a.question_index, p.name, a.correct
    from mine a
    join public.players p on p.id = a.player_id
    where a.blurted
    order by a.question_index, a.created_at
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
         c.name,
         c.correct
  from asked q
  left join tallied t on t.question_index = q.position
  left join wrong w on w.question_index = q.position
  left join claimed c on c.question_index = q.position
  order by case when coalesce(t.total, 0) = 0 then 0
                else round(100.0 * t.right_answers / t.total) end asc,
           q.position asc;
end;
$$;

grant execute on function public.game_report(uuid) to authenticated;
