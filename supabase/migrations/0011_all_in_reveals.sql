-- When the room is all in, reveal straight away.
--
-- A correct blurt already goes directly to the answer, and that snap is the best
-- moment in the game: the last thing that happens is somebody being right, and
-- then the answer is there. A question everyone has answered earned the same
-- treatment, but it was stopping on `locked` for a beat first — a pause whose
-- only content is the news that nothing is left to wait for.
--
-- The beat still belongs on the other path. When the clock runs out with answers
-- missing, "Time" is real information: it tells the room why the question ended.
-- That route still goes question_open -> locked -> results.
--
-- TO PUT THE BEAT BACK: set phase to 'locked' instead of 'results' below. The
-- host already advances locked -> results on its own after ~1.2s, and the wall
-- still knows how to say "All in" while it waits.

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

  -- An empty room would otherwise satisfy "everyone has answered" immediately and
  -- skip the question before anyone could join.
  if v_players = 0 or v_game.answered_count < v_players then
    return;
  end if;

  update public.games set phase = 'results'
  where id = p_game_id and phase = 'question_open';
end;
$$;
