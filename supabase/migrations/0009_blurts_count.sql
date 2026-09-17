-- A correct blurt is a correct answer, and the reveal should say so.
--
-- `distribution` counted answers by `choice`, and a blurt has no choice — it is
-- a spoken answer, not a tapped one. So a question won on a blurt showed four
-- zeroes and a tick, which reads as "nobody got it" directly above a scoreboard
-- where somebody clearly did.
--
-- A correct blurt now counts toward the answer it named. A wrong one still counts
-- nowhere: the student said something out loud that does not map to any of the
-- four options, and inventing a column for it would be a guess.

create or replace function public.distribution(p_code text)
returns table (answer_choice int, answer_count bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_correct int;
begin
  select * into v_game from public.games g where g.code = upper(trim(p_code));
  if not found or v_game.phase <> 'results' then
    return;
  end if;

  select q.correct_index into v_correct
  from public.questions q
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;

  return query
  select c.choice, count(a.id)
  from generate_series(0, 3) as c(choice)
  left join public.answers a
    on a.game_id = v_game.id
   and a.question_index = v_game.question_index
   and (
     a.choice = c.choice
     or (a.blurted and a.correct and c.choice = v_correct)
   )
  group by c.choice
  order by c.choice;
end;
$$;

-- The wall should be able to name who won it on a blurt, not just show the tally
-- move. `blurted_by` survives until the next question opens, so results can still
-- read it.
drop function if exists public.blurter(text);

create or replace function public.blurter(p_code text)
returns table (player_id uuid, player_name text, was_correct boolean)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id,
         p.name,
         coalesce(a.correct, false)
  from public.games g
  join public.players p on p.id = g.blurted_by
  left join public.answers a
    on a.game_id = g.id
   and a.player_id = p.id
   and a.question_index = g.question_index
   and a.blurted
  where g.code = upper(trim(p_code))
    and g.phase in ('blurt_claimed', 'results');
$$;

grant execute on function public.blurter(text) to anon, authenticated;
