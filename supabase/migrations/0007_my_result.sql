-- What a player is told about their own answer.
--
-- `answers` stays unreadable by anon, so a phone cannot look up how it did. This
-- returns one row about the caller and nobody else, and only once the room has
-- reached results — a student learning they were right while the question is
-- still open could tell the person next to them.

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
  with mine as (
    select a.question_index, a.correct, a.awarded, a.blurted,
           row_number() over (order by a.question_index desc) as recency
    from public.answers a
    where a.game_id = v_game.id and a.player_id = v_player.id
  ),
  this_one as (
    select * from mine where question_index = v_game.question_index
  )
  select
    exists (select 1 from this_one),
    coalesce((select t.correct from this_one t), false),
    coalesce((select t.awarded from this_one t), 0),
    coalesce((select t.blurted from this_one t), false),
    coalesce(
      (select (min(m.recency) filter (where not m.correct) - 1)::int from mine m),
      (select count(*)::int from mine)
    );
end;
$$;

grant execute on function public.my_result(uuid) to anon, authenticated;
