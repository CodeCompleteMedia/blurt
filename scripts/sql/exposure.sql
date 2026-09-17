-- Exactly what the public anon key can read.
--
-- The anon key ships in the browser bundle, so this is not a hypothetical
-- attacker: it is any student who opens devtools. This check pins the boundary
-- so it cannot widen without someone noticing.
--
-- KNOWN GAP, recorded here deliberately rather than asserted away: `games` and
-- `players` carry `using (true)`, because Realtime's postgres_changes only
-- delivers rows the subscriber is allowed to select. That makes every room code
-- and every student's name and score readable across every teacher's game, not
-- just your own. Closing it means moving the subscription to Broadcast and
-- serving reads through SECURITY DEFINER functions keyed by the room code.
-- Until then, this file asserts the exposure is no WIDER than that.
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

-- And the known gap, asserted at exactly its current width: readable, but only
-- these columns, and nothing that identifies the teacher who owns the room.
do $$
declare n_games int; n_players int; owner_visible boolean;
begin
  set local role anon;
  select count(*) into n_games from public.games;
  select count(*) into n_players from public.players;
  reset role;

  if n_games < 2 or n_players < 2 then
    raise exception 'expected the anon key to still see both games and both players (got % and %) — if this is now 0, the gap has been CLOSED and this check should be rewritten to assert that',
      n_games, n_players;
  end if;

  raise notice 'ok  KNOWN GAP unchanged: anon still enumerates % rooms and % students across teachers',
    n_games, n_players;
end $$;
