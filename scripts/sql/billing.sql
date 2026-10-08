-- A plan is a row the teacher cannot write, and every limit is checked in the
-- database at the moment of the action.
--
-- Three teachers: A pays, B is on Free, C is on Free and is the "someone else"
-- every ownership check needs. Each limit is reached the way a teacher with
-- devtools would reach it: the function, and the direct insert beside it.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'paid@example.test'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'free@example.test'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'other@example.test');

-- What the webhook writes for a teacher whose Checkout went through.
insert into public.teacher_plans (user_id, stripe_customer_id, stripe_subscription_id, status, billing_interval)
values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'cus_A', 'sub_A', 'active', 'month');

-- Runs one statement as a teacher, through the role the browser gets, and
-- reports what the database said: 'ok', or the error's SQLSTATE.
create function pg_temp.as_teacher(p_user text, p_sql text) returns text
language plpgsql as $$
declare v_state text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s"}', p_user), false);
  set local role authenticated;
  begin
    execute p_sql;
  exception when others then
    get stacked diagnostics v_state = returned_sqlstate;
    reset role;
    return v_state;
  end;
  reset role;
  return 'ok';
end $$;

create function pg_temp.expect(p_got text, p_want text, p_what text) returns void
language plpgsql as $$
begin
  if p_got is distinct from p_want then
    raise exception '%: expected %, got %', p_what, p_want, p_got;
  end if;
end $$;

-- ---------------------------------------------------------------- the row ---
do $$
declare
  a constant text := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  b constant text := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  r record;
begin
  -- 42501 is insufficient_privilege: the table itself is shut, to read or write.
  perform pg_temp.expect(pg_temp.as_teacher(b, 'select * from public.teacher_plans'), '42501', 'free teacher reading the plan table');
  perform pg_temp.expect(pg_temp.as_teacher(b,
    format('insert into public.teacher_plans (user_id, status) values (%L, ''active'')', b)), '42501', 'free teacher giving themselves a plan');
  perform pg_temp.expect(pg_temp.as_teacher(b,
    format('insert into public.teacher_plans (user_id, comp) values (%L, true)', b)), '42501', 'free teacher comping themselves');
  perform pg_temp.expect(pg_temp.as_teacher(a,
    'update public.teacher_plans set current_period_end = ''infinity'''), '42501', 'paid teacher extending their own plan');
  perform pg_temp.expect(pg_temp.as_teacher(b, 'update public.room_usage set rooms = 0'), '42501', 'free teacher resetting their room count');
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select public.plan_of(%L)', a)), '42501', 'asking about another teacher''s plan');
  perform pg_temp.expect(pg_temp.as_teacher(b, 'select * from public.plan_limits(''free'')'), '42501', 'calling the limits helper');

  perform set_config('request.jwt.claims', '', false);
  set local role anon;
  begin
    perform * from public.my_plan();
    raise exception 'the anon key read a plan';
  exception when insufficient_privilege then null;
  end;
  reset role;

  -- Each teacher is told their own plan and nothing of the other's.
  perform set_config('request.jwt.claims', format('{"sub":"%s"}', a), false);
  select * into r from public.my_plan();
  if r.plan <> 'teacher' or r.status <> 'active' or not r.has_customer or r.quiz_limit is not null or r.player_limit <> 60 then
    raise exception 'paid teacher sees %', r;
  end if;
  perform set_config('request.jwt.claims', format('{"sub":"%s"}', b), false);
  select * into r from public.my_plan();
  if r.plan <> 'free' or r.status is not null or r.has_customer or r.quiz_limit <> 2 or r.room_limit <> 3
     or r.player_limit <> 40 or r.report_days is not null or r.display_limit <> 1 then
    raise exception 'free teacher sees %', r;
  end if;

  raise notice 'ok  no client role can read or write a plan; each teacher is told only their own';
end $$;

-- ------------------------------------------------------- which statuses pay ---
do $$
declare
  c constant uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v record;
begin
  insert into public.teacher_plans (user_id) values (c);
  for v in select * from (values
    ('active', 'teacher'), ('trialing', 'teacher'), ('past_due', 'teacher'),
    ('canceled', 'free'), ('unpaid', 'free'), ('incomplete', 'free'),
    ('incomplete_expired', 'free'), ('paused', 'free'), (null, 'free')
  ) as s (status, plan) loop
    update public.teacher_plans set status = v.status where user_id = c;
    if public.plan_of(c) <> v.plan then
      raise exception 'status % gives %, expected %', v.status, public.plan_of(c), v.plan;
    end if;
  end loop;

  -- A paid status is believed only as far as the period Stripe last reported,
  -- and three days past it. This is what ends a plan when no webhook does.
  for v in select * from (values
    ('active',   interval '30 days',  'teacher'),
    ('active',   interval '-1 day',   'teacher'),
    ('active',   interval '-4 days',  'free'),
    ('past_due', interval '-4 days',  'free'),
    ('trialing', interval '-4 days',  'free'),
    ('canceled', interval '30 days',  'free')
  ) as s (status, ends, plan) loop
    update public.teacher_plans set status = v.status, current_period_end = now() + v.ends where user_id = c;
    if public.plan_of(c) <> v.plan then
      raise exception 'status % ending % gives %, expected %', v.status, v.ends, public.plan_of(c), v.plan;
    end if;
  end loop;

  -- A gift has no period, and does not run out with a subscription that has.
  update public.teacher_plans set comp = true where user_id = c;
  if public.plan_of(c) <> 'teacher' then raise exception 'a comped account is not on the Teacher plan'; end if;
  delete from public.teacher_plans where user_id = c;
  if public.plan_of(c) <> 'free' then raise exception 'no row should mean Free'; end if;
  if public.plan_of(null) <> 'free' then raise exception 'nobody should mean Free'; end if;

  raise notice 'ok  active, trialing and past_due pay until three days past the paid period; every other status, and no row, is Free';
end $$;

-- ----------------------------------------------------------------- quizzes ---
do $$
declare
  a constant text := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  b constant text := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  c constant text := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  v_quiz uuid;
  n int;
begin
  -- The sample, and one of their own.
  perform pg_temp.expect(pg_temp.as_teacher(b, 'select public.copy_sample_quiz()'), 'ok', 'free quiz 1 (sample)');
  perform pg_temp.expect(pg_temp.as_teacher(b, 'insert into public.quizzes (title) values (''Two'')'), 'ok', 'free quiz 2 (insert)');
  select id into v_quiz from public.quizzes where owner_id = b::uuid and title = 'Two';

  -- 23514 is check_violation. A third is refused by every route in.
  perform pg_temp.expect(pg_temp.as_teacher(b, 'insert into public.quizzes (title) values (''Four'')'), '23514', 'third quiz by insert');
  perform pg_temp.expect(pg_temp.as_teacher(b, 'select public.copy_sample_quiz()'), '23514', 'third quiz by sample');
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select public.duplicate_quiz(%L)', v_quiz)), '23514', 'third quiz by duplicate');

  -- Archiving makes room; restoring the archived one is then the third.
  perform pg_temp.expect(pg_temp.as_teacher(b, format('update public.quizzes set archived_at = now() where id = %L', v_quiz)), 'ok', 'archiving');
  perform pg_temp.expect(pg_temp.as_teacher(b, 'insert into public.quizzes (title) values (''Four'')'), 'ok', 'a quiz in the freed place');
  perform pg_temp.expect(pg_temp.as_teacher(b, format('update public.quizzes set archived_at = null where id = %L', v_quiz)), '23514', 'restoring past the limit');
  -- An ordinary edit at the limit is not an addition.
  perform pg_temp.expect(pg_temp.as_teacher(b, 'update public.quizzes set title = ''Renamed'' where title = ''Four'''), 'ok', 'renaming at the limit');

  select count(*) into n from public.quizzes where owner_id = b::uuid and archived_at is null;
  if n <> 2 then raise exception 'free teacher holds % live quizzes, expected 2', n; end if;

  -- The other free teacher's two are their own: B's do not count against C.
  for i in 1..2 loop
    perform pg_temp.expect(pg_temp.as_teacher(c, 'insert into public.quizzes (title) values (''Theirs'')'), 'ok', 'another free teacher''s quiz');
  end loop;
  perform pg_temp.expect(pg_temp.as_teacher(c, 'insert into public.quizzes (title) values (''Theirs'')'), '23514', 'another free teacher''s third');

  -- The paid teacher is not counted at all.
  for i in 1..6 loop
    perform pg_temp.expect(pg_temp.as_teacher(a, 'insert into public.quizzes (title) values (''Mine'')'), 'ok', 'paid quiz');
  end loop;
  perform pg_temp.expect(pg_temp.as_teacher(a, 'select public.copy_sample_quiz()'), 'ok', 'paid sample');

  raise notice 'ok  two quizzes on Free by insert, sample, duplicate and restore; no limit when paid';
end $$;

-- ------------------------------------------------------------------- games ---
do $$
declare
  a constant text := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  b constant text := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  c constant text := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  qa uuid; qb uuid; qc uuid;
  v_host uuid; v_game uuid;
  n int;
begin
  select id into qa from public.quizzes z where z.owner_id = a::uuid and exists (select 1 from public.questions q where q.quiz_id = z.id) limit 1;
  select id into qb from public.quizzes z where z.owner_id = b::uuid and exists (select 1 from public.questions q where q.quiz_id = z.id) limit 1;
  -- C's quizzes are empty; give one a question by copying B's.
  select id into qc from public.quizzes z where z.owner_id = c::uuid limit 1;
  insert into public.questions (quiz_id, position, kind, text, choices, correct_index, accepted, seconds, recall_seconds, blurt_enabled)
  select qc, position, kind, text, choices, correct_index, accepted, seconds, recall_seconds, blurt_enabled
  from public.questions where quiz_id = qb;

  -- Opening a room to look around costs nothing, and a second waiting room
  -- replaces the first.
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.create_game(%L)', qb)), 'ok', 'a free room, opened and left');
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.create_game(%L)', qb)), 'ok', 'a second free room');
  select count(*) into n from public.games g where g.owner_id = b::uuid and g.closed_at is null;
  if n <> 1 then raise exception 'a free teacher has % waiting rooms open, expected 1', n; end if;
  select coalesce(sum(rooms), 0) into n from public.room_usage where user_id = b::uuid;
  if n <> 0 then raise exception 'rooms nobody played were counted: %', n; end if;

  -- The room that was replaced cannot be started after all (0036), or a class
  -- seated in each waiting room would be a game each.
  select s.host_token into strict v_host
  from public.games g join public.game_secrets s on s.game_id = g.id
  where g.owner_id = b::uuid and g.closed_at is not null;
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select public.advance_game(%L)', v_host)), '23514', 'starting a closed waiting room');
  select coalesce(sum(rooms), 0) into n from public.room_usage where user_id = b::uuid;
  if n <> 0 then raise exception 'a refused start was counted: %', n; end if;

  -- Three games: each counts when its first question is asked, and only once.
  for i in 1..3 loop
    if i > 1 then
      perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.create_game(%L)', qb)), 'ok', 'free game ' || i);
    end if;
    select s.host_token into strict v_host
    from public.games g join public.game_secrets s on s.game_id = g.id
    where g.owner_id = b::uuid and g.question_index < 0 and g.closed_at is null;
    perform pg_temp.expect(pg_temp.as_teacher(b, format('select public.advance_game(%L)', v_host)), 'ok', 'starting free game ' || i);
    select sum(rooms) into n from public.room_usage where user_id = b::uuid;
    if n <> i then raise exception 'after starting game %, % are counted', i, n; end if;
  end loop;

  -- 23514 is check_violation. The fourth needs the Teacher plan.
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.create_game(%L)', qb)), '23514', 'a fourth free game');

  -- Deleting a game does not hand it back, and nor does a new month.
  select id into v_game from public.games where owner_id = b::uuid and question_index >= 0 limit 1;
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select public.delete_game(%L)', v_game)), 'ok', 'deleting a game');
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.create_game(%L)', qb)), '23514', 'a game after deleting one');
  update public.room_usage set month = (month - interval '1 month')::date where user_id = b::uuid;
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.create_game(%L)', qb)), '23514', 'a game in a new month');

  -- B's three are B's: the other free teacher has all of theirs. Left in the
  -- lobby for the students below.
  perform pg_temp.expect(pg_temp.as_teacher(c, format('select * from public.create_game(%L)', qc)), 'ok', 'another free teacher''s room');

  -- The paid teacher is not counted against anything, and keeps their lobbies.
  for i in 1..5 loop
    perform pg_temp.expect(pg_temp.as_teacher(a, format('select * from public.create_game(%L)', qa)), 'ok', 'paid game ' || i);
    select s.host_token into strict v_host
    from public.games g join public.game_secrets s on s.game_id = g.id
    where g.owner_id = a::uuid and g.question_index < 0 and g.closed_at is null;
    perform pg_temp.expect(pg_temp.as_teacher(a, format('select public.advance_game(%L)', v_host)), 'ok', 'starting paid game ' || i);
  end loop;
  perform pg_temp.expect(pg_temp.as_teacher(a, format('select * from public.create_game(%L)', qa)), 'ok', 'a paid waiting room');
  perform pg_temp.expect(pg_temp.as_teacher(a, format('select * from public.create_game(%L)', qa)), 'ok', 'a second paid waiting room');
  select count(*) into n from public.games g where g.owner_id = a::uuid and g.question_index < 0 and g.closed_at is null;
  if n <> 2 then raise exception 'a paid teacher has % waiting rooms, expected both kept', n; end if;

  raise notice 'ok  three games ever on Free, counted at the first question, not won back by deleting or by a closed room; no limit when paid';
end $$;

-- ------------------------------------------------------ students in a room ---
do $$
declare
  a constant uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  c constant uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  code_a text; code_c text;
  full_at int;
  v_cap int;
begin
  select g.code, g.player_cap into code_a, v_cap from public.games g
  where g.owner_id = a and g.question_index < 0 and g.closed_at is null limit 1;
  if v_cap <> 60 then raise exception 'a paid room opened with room for %, expected 60', v_cap; end if;
  select g.code, g.player_cap into code_c, v_cap from public.games g
  where g.owner_id = c and g.question_index < 0 and g.closed_at is null limit 1;
  if v_cap <> 40 then raise exception 'a free room opened with room for %, expected 40', v_cap; end if;

  -- Students join with the anon key, as they do from a phone.
  perform set_config('request.jwt.claims', '', false);
  set local role anon;
  full_at := null;
  for i in 1..45 loop
    begin
      perform * from public.join_game(code_c, 'Student ' || chr(64 + (i - 1) / 26 + 1) || chr(65 + (i - 1) % 26));
    exception when check_violation then
      full_at := i; exit;
    end;
  end loop;
  reset role;
  if full_at is distinct from 41 then raise exception 'a free room filled at student %, expected the 41st to be refused', full_at; end if;

  set local role anon;
  for i in 1..20 loop
    perform * from public.join_game(code_a, 'Student ' || chr(64 + i));
  end loop;
  reset role;

  -- The teacher of the full room upgrades: the next student gets in, same room.
  insert into public.teacher_plans (user_id, status) values (c, 'active');
  set local role anon;
  perform * from public.join_game(code_c, 'Forty First');
  reset role;

  -- The paying teacher lapses mid-lesson: their open room keeps its sixty.
  update public.teacher_plans set status = 'canceled' where user_id = a;
  set local role anon;
  perform * from public.join_game(code_a, 'Latecomer');
  reset role;

  raise notice 'ok  forty students on Free and sixty when paid; an upgrade opens the room, a lapse does not shrink it';
end $$;

-- ------------------------------------------------- a lapse, and coming back ---
do $$
declare
  a constant text := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  qa uuid;
  code_a text; host_a uuid;
  n int;
begin
  -- A is now cancelled, with seven quizzes, five games played, and a room of
  -- twenty-one students waiting in the lobby.
  select g.code, s.host_token into code_a, host_a
  from public.games g join public.game_secrets s on s.game_id = g.id
  join public.players p on p.game_id = g.id
  where g.owner_id = a::uuid and g.question_index < 0 and g.closed_at is null limit 1;
  select quiz_id into qa from public.games where code = code_a;

  -- They have had more than Free's three games, so the next room is refused,
  -- and so is the next quiz. Being refused closed nothing.
  perform pg_temp.expect(pg_temp.as_teacher(a, format('select * from public.create_game(%L)', qa)), '23514', 'the next room after a lapse');
  perform pg_temp.expect(pg_temp.as_teacher(a, 'insert into public.quizzes (title) values (''One more'')'), '23514', 'the next quiz after a lapse');
  if (select closed_at from public.games where code = code_a) is not null then
    raise exception 'a refused room closed the one that was waiting';
  end if;

  -- The room already open runs on: the host still reads it and can start it.
  perform pg_temp.expect(pg_temp.as_teacher(a, format('select * from public.host_question(%L)', host_a)), 'ok', 'reading the open room after a lapse');
  perform pg_temp.expect(pg_temp.as_teacher(a, format('select public.advance_game(%L)', host_a)), 'ok', 'starting the open room after a lapse');

  -- Nothing was taken away: all seven quizzes are still there and still theirs.
  select count(*) into n from public.quizzes where owner_id = a::uuid and archived_at is null;
  if n <> 7 then raise exception 'a lapsed teacher holds % quizzes, expected the 7 they made', n; end if;
  perform pg_temp.expect(pg_temp.as_teacher(a, 'update public.quizzes set title = ''Edited'' where title = ''Mine'''), 'ok', 'editing after a lapse');

  -- Stripe retrying the card is not a lapse.
  update public.teacher_plans set status = 'past_due' where user_id = a::uuid;
  perform pg_temp.expect(pg_temp.as_teacher(a, format('select * from public.create_game(%L)', qa)), 'ok', 'a room while the card is retried');

  raise notice 'ok  a lapse blocks the next room and the next quiz, never the open room, and deletes nothing';
end $$;

-- ----------------------------------------------------------------- reports ---
do $$
declare
  b constant text := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  v_old uuid;
  n int;
begin
  -- Free keeps the reports of its three games, however old. The machinery for
  -- a plan that reads only so far back (0034) is still there; no plan uses it.
  select id into v_old from public.games where owner_id = b::uuid and question_index >= 0 order by id limit 1;
  update public.games set created_at = now() - interval '400 days' where id = v_old;

  perform set_config('request.jwt.claims', format('{"sub":"%s"}', b), false);
  select count(*) into n from public.my_games() where game_id = v_old;
  if n <> 1 then raise exception 'a free teacher''s old game is not listed'; end if;
  if public.my_hidden_games() <> 0 then raise exception 'Free is hiding % games', public.my_hidden_games(); end if;

  perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.game_summary(%L)', v_old)), 'ok', 'old summary on Free');
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.game_report(%L)', v_old)), 'ok', 'old report on Free');
  perform pg_temp.expect(pg_temp.as_teacher(b, format('select * from public.game_players(%L)', v_old)), 'ok', 'old students on Free');

  raise notice 'ok  Free keeps the reports of the games it played';
end $$;

-- ---------------------------------------------------------------- displays ---
do $$
declare
  a constant text := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  b constant text := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
begin
  perform pg_temp.expect(pg_temp.as_teacher(b, 'select * from public.create_wall(''Front'')'), 'ok', 'free display 1');
  perform pg_temp.expect(pg_temp.as_teacher(b, 'select * from public.create_wall(''Back'')'), '23514', 'free display 2');

  update public.teacher_plans set status = 'active' where user_id = a::uuid;
  for i in 1..10 loop
    perform pg_temp.expect(pg_temp.as_teacher(a, 'select * from public.create_wall(''Room'')'), 'ok', 'paid display ' || i);
  end loop;
  if pg_temp.as_teacher(a, 'select * from public.create_wall(''Eleven'')') = 'ok' then
    raise exception 'an eleventh display was paired';
  end if;

  raise notice 'ok  one paired display on Free, ten when paid';
end $$;

-- ------------------------------------------------------------------- admin ---
do $$
declare
  a constant uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
  b constant uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  c constant uuid := 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  r record;
  refused boolean := false;
begin
  insert into public.platform_admins (user_id) values (c);
  perform set_config('request.jwt.claims', format('{"sub":"%s"}', c), false);

  select * into r from public.admin_teachers() t where t.user_id = a;
  if r.plan <> 'teacher' or r.plan_status <> 'active' or r.stripe_customer_id <> 'cus_A' then
    raise exception 'admin sees the paid teacher as %', r;
  end if;
  select * into r from public.admin_teachers() t where t.user_id = b;
  if r.plan <> 'free' or r.plan_status is not null or r.stripe_customer_id is not null then
    raise exception 'admin sees the free teacher as %', r;
  end if;

  -- Stripe would go on charging a card for an account that is gone.
  begin perform public.admin_delete_teacher(a);
  exception when check_violation then refused := true; end;
  if not refused then raise exception 'a teacher with a live subscription was deleted'; end if;

  update public.teacher_plans set status = 'canceled' where user_id = a;
  perform public.admin_delete_teacher(a);
  if exists (select 1 from public.teacher_plans where user_id = a) then
    raise exception 'the plan row outlived its teacher';
  end if;

  raise notice 'ok  the admin sees plan, status and customer; a live subscription must be cancelled before a delete';
end $$;
