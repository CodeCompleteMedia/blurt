-- Ending a room, so the wall and the phones find out.
--
-- Starting a new room used to abandon everyone quietly: /present/OLDCODE kept
-- showing a game nobody was playing, and every phone stayed seated in it. Both
-- are addressed by code or by token, so neither can discover the new room on its
-- own — they need to be told the old one is over.
--
-- `closed_at` rather than a new phase: the phase records where the game actually
-- stopped, which is worth keeping for the reports in a later phase. A room
-- abandoned at question three should still say question three.

alter table public.games add column closed_at timestamptz;

create or replace function public.close_game(p_host_token uuid)
returns void
language plpgsql
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

  update public.games set closed_at = now()
  where id = v_game.id and closed_at is null;
end;
$$;

-- Nobody may join a room that has been closed.
create or replace function public.join_game(p_code text, p_name text)
returns table (player_id uuid, player_token uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_player public.players;
  v_token uuid;
begin
  select * into v_game from public.games where code = upper(trim(p_code));
  if not found then
    raise exception 'no such room' using errcode = 'no_data_found';
  end if;

  if v_game.closed_at is not null then
    raise exception 'that room has closed' using errcode = 'check_violation';
  end if;

  if v_game.phase = 'final' then
    raise exception 'that game has finished' using errcode = 'check_violation';
  end if;

  if v_game.phase <> 'lobby' and not v_game.allow_late_join then
    raise exception 'that game has already started' using errcode = 'check_violation';
  end if;

  insert into public.players (game_id, name) values (v_game.id, trim(p_name))
  returning * into v_player;

  insert into public.player_secrets (player_id) values (v_player.id)
  returning player_secrets.token into v_token;

  return query select v_player.id, v_token;
exception
  when unique_violation then
    raise exception 'someone in this room already has that name'
      using errcode = 'unique_violation';
end;
$$;

grant execute on function public.close_game(uuid) to anon, authenticated;
