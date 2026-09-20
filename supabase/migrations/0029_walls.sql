-- A display you set up once.
--
-- `/present/CODE` is a screen, not a session: it holds no credential and the code
-- in the path is the whole key. That is right for a projector driven by the same
-- browser as the host, but it means a classroom PC at the front of the room has
-- to be told a new five-letter code every lesson, by hand, while thirty people
-- watch.
--
-- A wall is the other half of that. It is a stable id the teacher opens once on
-- whatever machine drives the projector, and afterwards the host points rooms at
-- it. The wall still holds no credential and still learns nothing but a room
-- code — the same thing it would have been told out loud.
--
-- Pointing is announced over Broadcast for the instant case and written to the
-- row for the reliable one. The wall subscribes AND polls, for the same reason
-- everything else here does: a school network that idles out a websocket must
-- not strand a projector.

create table public.walls (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users (id) on delete cascade,
  label text not null check (length(btrim(label)) between 1 and 40),
  -- The room it is currently showing. Null until it is pointed somewhere.
  code text,
  pointed_at timestamptz,
  created_at timestamptz not null default now()
);

create index walls_owner on public.walls (owner_id);

alter table public.walls enable row level security;
-- No policies on purpose. Every read and write goes through the functions below,
-- because one of them has to be callable by the anon key and the rest must not.

-- A teacher's own displays.
create or replace function public.create_wall(p_label text)
returns table (wall_id uuid, label text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_label text := btrim(coalesce(p_label, ''));
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;
  if length(v_label) = 0 then
    raise exception 'give the display a name you will recognise';
  end if;
  -- A teacher has a handful of rooms, not a hundred. The cap is here so a bug
  -- in a loop cannot fill the table.
  if (select count(*) from public.walls w where w.owner_id = auth.uid()) >= 10 then
    raise exception 'ten displays is already more rooms than anyone teaches in';
  end if;

  insert into public.walls (owner_id, label) values (auth.uid(), left(v_label, 40))
  returning id into v_id;

  return query select v_id, left(v_label, 40);
end;
$$;

grant execute on function public.create_wall(text) to authenticated;

create or replace function public.my_walls()
returns table (wall_id uuid, label text, code text, pointed_at timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select w.id, w.label, w.code, w.pointed_at
  from public.walls w
  where w.owner_id = auth.uid()
  order by w.created_at;
$$;

grant execute on function public.my_walls() to authenticated;

create or replace function public.rename_wall(p_wall_id uuid, p_label text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_label text := btrim(coalesce(p_label, ''));
begin
  if length(v_label) = 0 then
    raise exception 'give the display a name you will recognise';
  end if;
  update public.walls w set label = left(v_label, 40)
  where w.id = p_wall_id and w.owner_id = auth.uid();
  if not found then
    raise exception 'that is not your display' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

grant execute on function public.rename_wall(uuid, text) to authenticated;

create or replace function public.delete_wall(p_wall_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.walls w where w.id = p_wall_id and w.owner_id = auth.uid();
  if not found then
    raise exception 'that is not your display' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

grant execute on function public.delete_wall(uuid) to authenticated;

-- Send a room to a display.
--
-- Gated twice over: the caller must own the display, and must hold the host
-- token of the game they are sending. Owning one without the other is not
-- enough, or a teacher could push their room onto a colleague's projector.
create or replace function public.point_wall(p_wall_id uuid, p_host_token uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
begin
  select g.code into v_code
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token and g.owner_id = auth.uid();

  if v_code is null then
    raise exception 'not the host of that room' using errcode = 'insufficient_privilege';
  end if;

  update public.walls w
  set code = v_code, pointed_at = now()
  where w.id = p_wall_id and w.owner_id = auth.uid();

  if not found then
    raise exception 'that is not your display' using errcode = 'insufficient_privilege';
  end if;

  -- Instant for a wall that is listening; the row above is what a wall that
  -- missed it will find on its next poll.
  perform realtime.send(
    jsonb_build_object('code', v_code), 'pointed', 'wall:' || p_wall_id::text, true);
end;
$$;

grant execute on function public.point_wall(uuid, uuid) to authenticated;

-- What the display itself asks, holding nothing but its own id.
--
-- This is the one function here the anon key may call, because a projector has
-- no account. It hands back the display's name and the room it has been pointed
-- at — a room code, which is the same thing the wall would otherwise have had
-- read out to it, and which is about to be twenty centimetres tall on the wall
-- anyway.
create or replace function public.wall_room(p_wall_id uuid)
returns table (label text, code text, pointed_at timestamptz)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select w.label, w.code, w.pointed_at
  from public.walls w
  where w.id = p_wall_id;
$$;

grant execute on function public.wall_room(uuid) to anon, authenticated;

-- A correction to 0016.
--
-- That migration closed two helpers by name and then wrote
--
--   alter default privileges in schema public revoke execute on functions ...
--
-- believing the next function would start closed. It does not. Verified on
-- PostgreSQL 16.14, with and without `for role`: the statement registers no row
-- in pg_default_acl and a function created afterwards still carries the built-in
-- default, which is EXECUTE to PUBLIC. Every function since has relied on its
-- own explicit grant or revoke — which, checked one by one, every function has
-- had, bar the trigger below. Postgres refuses to call a trigger function
-- directly anyway ("trigger functions can only be called as triggers"), so
-- nothing was reachable that should not have been. Closing it regardless, so
-- that "no function is left on the default" is a property a check can assert
-- rather than a sentence in a comment. See scripts/sql/overloads.sql.
revoke execute on function public.reset_question_state() from public, anon, authenticated;

-- Displays listen on their own topic, rooms on theirs.
drop policy if exists blurt_rooms_subscribable on realtime.messages;
create policy blurt_rooms_subscribable on realtime.messages
  for select to anon, authenticated
  using (realtime.topic() like 'blurt:%' or realtime.topic() like 'wall:%');
