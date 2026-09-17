-- Pushing changes without letting anyone read the table.
--
-- postgres_changes can only deliver rows the subscriber is allowed to select,
-- which is why `games` and `players` were readable by everyone. Broadcast has no
-- such tie: the database decides what goes out and to which topic, and the topic
-- is the room code.
--
-- What goes out is a bare signal, not the row. The client re-reads through
-- `game_state`/`roster` exactly as the poll underneath already does, so there is
-- one code path rather than two, and the message itself carries nothing — a
-- payload that leaks is a payload that cannot leak if it is empty.

create or replace function public.announce_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
begin
  if tg_table_name = 'games' then
    v_code := coalesce(new.code, old.code);
  else
    select g.code into v_code from public.games g
    where g.id = coalesce(new.game_id, old.game_id);
  end if;

  if v_code is not null then
    -- Empty payload on purpose: the signal says "something moved", and the
    -- reader asks what. private => the subscriber must pass the RLS policy below.
    perform realtime.send('{}'::jsonb, 'changed', 'blurt:' || v_code, true);
  end if;

  return null;
end;
$$;

revoke execute on function public.announce_change() from public, anon, authenticated;

create trigger games_announce
  after update on public.games
  for each row execute function public.announce_change();

-- A student joining, being renamed, scoring or being removed all change the
-- roster, and the lobby is the one screen where a slow update is obvious.
create trigger players_announce
  after insert or update or delete on public.players
  for each row execute function public.announce_change();

-- Who may listen. Broadcast delivery is a select on realtime.messages, so this
-- is the whole access rule: you may subscribe to a room if you can name it.
-- The room code is the secret, which is the same thing joining a room has
-- always relied on — and unlike the table read it replaces, a topic cannot be
-- enumerated, so knowing one room tells you nothing about any other.
drop policy if exists blurt_rooms_subscribable on realtime.messages;
create policy blurt_rooms_subscribable on realtime.messages
  for select to anon, authenticated
  using (realtime.topic() like 'blurt:%');

grant select on realtime.messages to anon, authenticated;
