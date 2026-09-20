-- A display belongs to one teacher, and only that teacher can aim it.
--
-- The wall itself has no account — it holds a uuid and nothing else — so
-- `wall_room` is anon-callable by design. Everything else here must not be.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select public.copy_sample_quiz() as qa \gset
select code as ca, host_token as ha from public.create_game(:'qa') \gset
select set_config('blurt.ha', :'ha', false) \gset x
select set_config('blurt.ca', :'ca', false) \gset x

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false) \gset x
select public.copy_sample_quiz() as qb \gset
select code as cb, host_token as hb from public.create_game(:'qb') \gset
select set_config('blurt.hb', :'hb', false) \gset x

do $$
declare
  mine uuid; theirs uuid; r record; n int; refused boolean;
begin
  -- Each teacher makes a display.
  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);
  select w.wall_id into mine from public.create_wall('Front projector') w;

  perform set_config('request.jwt.claims',
    '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false);
  select w.wall_id into theirs from public.create_wall('Their room') w;

  -- Each sees only their own.
  select count(*) into n from public.my_walls();
  if n <> 1 then raise exception 'teacher B sees % displays, expected 1', n; end if;

  -- B cannot aim A's display, even holding their own host token.
  refused := false;
  begin perform public.point_wall(mine, current_setting('blurt.hb')::uuid);
  exception when insufficient_privilege then refused := true; end;
  if not refused then raise exception 'another teacher aimed my display'; end if;

  -- Nor rename or delete it.
  refused := false;
  begin perform public.rename_wall(mine, 'hijacked');
  exception when insufficient_privilege then refused := true; end;
  if not refused then raise exception 'another teacher renamed my display'; end if;

  refused := false;
  begin perform public.delete_wall(mine);
  exception when insufficient_privilege then refused := true; end;
  if not refused then raise exception 'another teacher deleted my display'; end if;

  -- A owns the display but must also hold the host token of the room being sent,
  -- or owning a display would be enough to broadcast someone else's game.
  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);
  refused := false;
  begin perform public.point_wall(mine, current_setting('blurt.hb')::uuid);
  exception when insufficient_privilege then refused := true; end;
  if not refused then
    raise exception 'a teacher sent a room they do not host to their own display';
  end if;

  -- The real thing.
  delete from realtime.messages;
  perform public.point_wall(mine, current_setting('blurt.ha')::uuid);

  select * into r from public.wall_room(mine);
  if r.code is distinct from current_setting('blurt.ca') then
    raise exception 'the display is showing %, expected %', r.code, current_setting('blurt.ca');
  end if;
  if r.label <> 'Front projector' then
    raise exception 'the display forgot its name: %', r.label;
  end if;

  -- And it was announced on its own topic, not the room's and not another's.
  select count(*) into n from realtime.messages m
   where m.topic = 'wall:' || mine::text and m.event = 'pointed';
  if n <> 1 then raise exception 'expected one announcement on the display topic, got %', n; end if;

  select count(*) into n from realtime.messages m where m.topic = 'wall:' || theirs::text;
  if n <> 0 then raise exception '% messages reached another teacher''s display', n; end if;

  raise notice 'ok  a display is owned, aimed only by its owner holding the host token, and announced on its own topic';
end $$;

-- What the projector can do holding only its id, and what it cannot.
do $$
declare
  mine uuid;
  r record;
  n int;
  reachable text := '';
  fn text;
begin
  select w.wall_id into mine from public.my_walls() w limit 1;
  perform set_config('blurt.wall', mine::text, false);

  perform set_config('request.jwt.claims', '', false);
  set local role anon;

  -- It can ask where it is pointed. That is the whole contract.
  select * into r from public.wall_room(current_setting('blurt.wall')::uuid);
  if r.code is null then raise exception 'the display cannot read its own room'; end if;
  reset role;

  -- It cannot do anything else, and cannot read the table behind it.
  foreach fn in array array['my_walls', 'walls'] loop
    begin
      set local role anon;
      if fn = 'walls' then
        execute 'select count(*) from public.walls' into n;
      else
        execute 'select count(*) from public.my_walls()' into n;
      end if;
      reset role;
      if n <> 0 then reachable := reachable || ' ' || fn || '(' || n || ' rows)'; end if;
    exception when insufficient_privilege then
      reset role;
    end;
  end loop;

  if reachable <> '' then
    raise exception 'the anon key reached:%', reachable;
  end if;

  raise notice 'ok  a display reads its own room and nothing else';
end $$;

-- An unknown id is not an error and not a door.
do $$
declare n int;
begin
  set local role anon;
  select count(*) into n from public.wall_room('00000000-0000-0000-0000-000000000000');
  reset role;
  if n <> 0 then raise exception 'an id that is not a display returned % rows', n; end if;
  raise notice 'ok  an id that is not a display returns nothing';
end $$;
