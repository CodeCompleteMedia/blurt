-- Exactly what the public anon key can read.
--
-- The anon key ships in the browser bundle, so this is not a hypothetical
-- attacker: it is any student who opens devtools. This check pins the boundary
-- so it cannot widen without someone noticing.
--
-- The gap this file was written to record is now closed. `games` and `players`
-- carried `using (true)` because postgres_changes only delivers rows the
-- subscriber may select; 0028 moved that to Broadcast and 0027 shut the tables,
-- so a room is reachable only by naming its code.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select public.copy_sample_quiz() as qa \gset
select code as ca, host_token as ha from public.create_game(:'qa') \gset
select public.join_game(:'ca', 'Rosa') \gset x

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false) \gset x
select public.copy_sample_quiz() as qb \gset
select code as cb, host_token as hb from public.create_game(:'qb') \gset
select public.join_game(:'cb', 'Dev') \gset x

select set_config('blurt.code_a', :'ca', false) \gset x
select set_config('blurt.code_b', :'cb', false) \gset x

-- Nothing but the anon key from here on.
select set_config('request.jwt.claims', '', false) \gset x

do $$
declare
  t text;
  n int;
  leaked text := '';
begin
  -- Tokens, correct answers and who-picked-what must be unreachable. These are
  -- the five that hold something worth cheating for.
  foreach t in array array['answers', 'game_secrets', 'player_secrets',
                           'questions', 'quizzes', 'game_questions'] loop
    begin
      set local role anon;
      execute format('select count(*) from public.%I', t) into n;
      reset role;
      if n <> 0 then
        leaked := leaked || format(e'\n       %s (%s rows)', t, n);
      end if;
    exception when insufficient_privilege then
      reset role;
    end;
  end loop;

  if leaked <> '' then
    raise exception 'the anon key can read tables it must not:%', leaked;
  end if;
  raise notice 'ok  answers, secrets, questions, quizzes and the snapshot are all refused';
end $$;

-- No table in the schema may be addressable by the anon key at all.
--
-- anon is the role the key in the browser bundle resolves to, so this is the
-- one that has to be empty. `authenticated` is deliberately different: a teacher
-- has a real account, and RLS scopes `quizzes` and `questions` to rows they own.
-- Students never sign in, so they never reach that role.
--
-- Zero rows is not the same as no grant. RLS with no policies denies everyone,
-- so a table left granted reads as safe from outside right up until somebody
-- adds a convenience policy to it. `walls` shipped in 0029 without its revoke
-- and nothing caught it: the check looked for rows rather than for the grant,
-- and the throwaway database did not model Supabase's habit of handing new
-- tables to anon. Both are fixed; this is the half that bites.
do $$
declare open_tables text := '';
begin
  select string_agg(format(e'\n       %s', c.relname), '' order by c.relname)
    into open_tables
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public' and c.relkind = 'r'
    and has_table_privilege('anon', c.oid, 'select');

  if open_tables is not null then
    raise exception 'table(s) still granted SELECT to anon — only RLS is holding them shut:%',
      open_tables;
  end if;

  raise notice 'ok  no table in the schema is addressable by the anon key';
end $$;

-- Every table `authenticated` can read must have policies to scope it, or the
-- grant is doing nothing but waiting for someone to notice it.
do $$
declare unscoped text := '';
begin
  select string_agg(format(e'\n       %s', c.relname), '' order by c.relname)
    into unscoped
  from pg_class c
  join pg_namespace ns on ns.oid = c.relnamespace
  where ns.nspname = 'public' and c.relkind = 'r'
    and has_table_privilege('authenticated', c.oid, 'select')
    and not exists (select 1 from pg_policy pol where pol.polrelid = c.oid);

  if unscoped <> '' and unscoped is not null then
    raise exception 'table(s) readable by a signed-in user with no policy to scope them:%', unscoped;
  end if;

  raise notice 'ok  every table a signed-in teacher can read is scoped by policy';
end $$;

-- No credential may live on a row the anon key can read. This is the reason
-- secrets were split into their own tables in the first place, and the check
-- that says the split still holds.
do $$
declare bad text;
begin
  select string_agg(format('%s.%s', table_name, column_name), ', ')
    into bad
  from information_schema.columns
  where table_schema = 'public'
    and table_name in ('games', 'players')
    and (column_name ilike '%token%' or column_name ilike '%secret%');

  if bad is not null then
    raise exception 'a credential column sits on an anon-readable table: %', bad;
  end if;
  raise notice 'ok  no token or secret column on games or players';
end $$;

-- The tables themselves are now shut, and the room is reached by its code.
do $$
declare
  n int;
  t text;
  still_open text := '';
  v_code text := current_setting('blurt.code_a');
  r record;
begin
  foreach t in array array['games', 'players'] loop
    begin
      set local role anon;
      execute format('select count(*) from public.%I', t) into n;
      reset role;
      still_open := still_open || format(e'\n       %s (%s rows)', t, n);
    exception when insufficient_privilege then
      reset role;
    end;
  end loop;

  if still_open <> '' then
    raise exception 'the anon key can still enumerate:%', still_open;
  end if;
  raise notice 'ok  games and players are no longer readable as tables';
end $$;

-- But knowing the code still gets you the room, or every phone in the class
-- stops working.
do $$
declare r record; n int;
begin
  set local role anon;
  select * into r from public.game_state(current_setting('blurt.code_a'));
  if r.code is null or r.phase is null then
    raise exception 'the room could not be read with its own code';
  end if;
  if r.code <> current_setting('blurt.code_a') then
    raise exception 'game_state returned room % for code %', r.code, current_setting('blurt.code_a');
  end if;

  select count(*) into n from public.roster(current_setting('blurt.code_a'));
  if n <> 1 then raise exception 'the roster for this room has % students, expected 1', n; end if;

  -- And the code is the whole key: another room's code gives another room, and
  -- a code that is not a room gives nothing rather than everything.
  select count(*) into n from public.roster(current_setting('blurt.code_b'));
  if n <> 1 then raise exception 'the other room''s roster has % students, expected 1', n; end if;

  select count(*) into n from public.game_state('ZZZZZ');
  if n <> 0 then raise exception 'a code that is not a room returned % rows', n; end if;
  select count(*) into n from public.roster('ZZZZZ');
  if n <> 0 then raise exception 'a code that is not a room returned % students', n; end if;
  reset role;

  raise notice 'ok  a room is reachable by its code, and only by its code';
end $$;

-- No credential and no owner on what the code hands back: game_state is the new
-- public surface, so it is the thing that must not grow a token column.
do $$
declare bad text;
begin
  select string_agg(a.attname, ', ') into bad
  from pg_proc p
  join unnest(p.proallargtypes, p.proargnames) with ordinality as a(typ, attname, ord) on true
  join pg_namespace ns on ns.oid = p.pronamespace
  where ns.nspname = 'public' and p.proname = 'game_state'
    and (a.attname ilike '%token%' or a.attname ilike '%secret%' or a.attname = 'owner_id');

  if bad is not null then
    raise exception 'game_state hands out %', bad;
  end if;
  raise notice 'ok  game_state exposes no token, secret or owner';
end $$;
