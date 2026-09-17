-- Changes are announced on the room's own topic, and carry nothing.
--
-- LIMIT OF THIS CHECK: the local `realtime` schema is a stub that records what
-- was sent. It proves the trigger fires, builds the right topic, and puts no
-- data in the message. Whether a browser actually receives it can only be
-- proven against a real Supabase project — see the note in supabase-stubs.sql.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select public.copy_sample_quiz() as qa \gset
select code as ca, host_token as ha from public.create_game(:'qa') \gset
select set_config('blurt.code_a', :'ca', false) \gset x
select set_config('blurt.host_a', :'ha', false) \gset x

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false) \gset x
select public.copy_sample_quiz() as qb \gset
select code as cb, host_token as hb from public.create_game(:'qb') \gset
select set_config('blurt.code_b', :'cb', false) \gset x

do $$
declare
  v_a text := current_setting('blurt.code_a');
  v_b text := current_setting('blurt.code_b');
  v_host uuid := current_setting('blurt.host_a')::uuid;
  n int; n_other int; bad text;
begin
  delete from realtime.messages;

  -- A student arriving changes the lobby.
  perform public.join_game(v_a, 'Rosa');
  select count(*) into n from realtime.messages where topic = 'blurt:' || v_a;
  if n < 1 then raise exception 'a student joined and nothing was announced'; end if;

  -- The phase moving is the one that must never be missed: it is what advances
  -- the projector.
  delete from realtime.messages;
  perform public.advance_game(v_host);
  select count(*) into n from realtime.messages
   where topic = 'blurt:' || v_a and event = 'changed';
  if n < 1 then raise exception 'the game advanced and nothing was announced'; end if;

  -- Nothing reached the other teacher's room.
  select count(*) into n_other from realtime.messages where topic = 'blurt:' || v_b;
  if n_other <> 0 then
    raise exception '% messages went to another teacher''s room', n_other;
  end if;

  -- And the message carries no data at all.
  select string_agg(distinct payload::text, ', ') into bad
  from realtime.messages where payload::text <> '{}';
  if bad is not null then
    raise exception 'the broadcast payload carries data: %', bad;
  end if;

  if exists (select 1 from realtime.messages where not private) then
    raise exception 'a message went out on a public topic, bypassing the subscribe policy';
  end if;

  raise notice 'ok  joins and phase changes announce on the room''s own topic, with an empty payload';
end $$;

-- The subscribe rule itself: broadcast delivery is a select on
-- realtime.messages, so this policy is the entire access check.
do $$
declare v_using text; v_roles text;
begin
  select pg_get_expr(pol.polqual, pol.polrelid),
         array_to_string(array(select rolname from pg_roles where oid = any(pol.polroles)), ', ')
    into v_using, v_roles
  from pg_policy pol
  join pg_class c on c.oid = pol.polrelid
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'realtime' and c.relname = 'messages'
    and pol.polname = 'blurt_rooms_subscribable';

  if v_using is null then
    raise exception 'there is no policy saying who may subscribe to a room';
  end if;
  if v_using not like '%blurt:%' then
    raise exception 'the subscribe policy does not scope to blurt topics: %', v_using;
  end if;
  if v_roles not like '%anon%' then
    raise exception 'students hold only the anon key, and the policy covers: %', v_roles;
  end if;

  raise notice 'ok  subscribing is scoped to blurt topics and granted to anon';
end $$;

-- The announcer must not be callable directly: it is a trigger, and a function
-- that sends messages on any topic is not something to hand the room.
do $$
begin
  if has_function_privilege('anon', 'public.announce_change()', 'execute')
     or has_function_privilege('authenticated', 'public.announce_change()', 'execute') then
    raise exception 'the announcer is callable from the browser';
  end if;
  raise notice 'ok  the announcer is a trigger only, not an API';
end $$;
