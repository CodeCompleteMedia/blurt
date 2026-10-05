-- The platform admin sees across every teacher, and nobody else does.
--
-- Three teachers and two admins. B runs a room with two students and one
-- answer; C has only a quiz. Every admin function must refuse B (signed in, not
-- an admin) and anon outright; the admin's numbers must count all of them; and
-- deleting B must take exactly B's things, leaving C untouched.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id, email, email_confirmed_at) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'admin@school.test', now()),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'b@school.test', now()),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'c@school.test', null),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'second-admin@school.test', now());
insert into public.platform_admins (user_id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('dddddddd-dddd-dddd-dddd-dddddddddddd');
insert into auth.sessions (user_id) values
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

-- B: a quiz and a room with two students, one of whom answers.
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false) \gset x
select public.copy_sample_quiz() as qb \gset
select code as cb, host_token as hb from public.create_game(:'qb') \gset
select set_config('blurt.cb', :'cb', false) \gset x
select set_config('blurt.hb', :'hb', false) \gset x

do $$
declare p1 record; p2 record; hb uuid := current_setting('blurt.hb')::uuid; cb text := current_setting('blurt.cb');
begin
  perform public.update_game_settings(hb, false);   -- no recall: straight to the choices
  select * into p1 from public.join_game(cb, 'Rosa');
  select * into p2 from public.join_game(cb, 'Dev');
  perform public.advance_game(hb);
  perform public.submit_answer(p1.player_token, 1);
end $$;

-- C: a quiz, no rooms.
select set_config('request.jwt.claims', '{"sub":"cccccccc-cccc-cccc-cccc-cccccccccccc"}', false) \gset x
select public.copy_sample_quiz() as qc \gset

-- Not an admin, or not signed in: every admin function is refused.
do $$
declare
  calls text[] := array[
    'select * from public.admin_overview()',
    'select * from public.admin_signups(30)',
    'select * from public.admin_teachers()',
    'select public.admin_suspend_teacher(''cccccccc-cccc-cccc-cccc-cccccccccccc'', true)',
    'select public.admin_delete_teacher(''cccccccc-cccc-cccc-cccc-cccccccccccc'')'
  ];
  c text; who text; refused boolean;
begin
  foreach who in array array['authenticated', 'anon'] loop
    foreach c in array calls loop
      perform set_config('request.jwt.claims',
        case when who = 'anon' then '' else '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}' end, true);
      refused := false;
      begin
        execute format('set local role %I', who);
        execute c;
      exception when insufficient_privilege then refused := true;
      end;
      reset role;
      if not refused then raise exception '% was allowed to run: %', who, c; end if;
    end loop;
  end loop;

  -- Asking "am I an admin?" is fine, and the answer is no.
  perform set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', true);
  set local role authenticated;
  if public.is_platform_admin() then raise exception 'a teacher was told they are an admin'; end if;
  reset role;

  -- And the list itself is not readable.
  refused := false;
  begin
    set local role authenticated;
    perform count(*) from public.platform_admins;
  exception when insufficient_privilege then refused := true;
  end;
  reset role;
  if not refused then raise exception 'a teacher could read the admin list'; end if;

  raise notice 'ok  a teacher and anon are refused every admin function and the admin list';
end $$;

-- The admin's view counts everyone, students included, and names no student.
do $$
declare o record; b record; n int; today int;
begin
  perform set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', true);
  set local role authenticated;
  if not public.is_platform_admin() then raise exception 'the admin was not recognised'; end if;

  select * into o from public.admin_overview();
  if o.teachers <> 4 or o.confirmed <> 3 or o.signups_7d <> 4 then
    raise exception 'teacher counts wrong: % total, % confirmed, % this week', o.teachers, o.confirmed, o.signups_7d;
  end if;
  if o.rooms_total <> 1 or o.active_30d <> 1 or o.students_total <> 2 or o.answers_total <> 1 or o.quizzes_total <> 2 then
    raise exception 'usage wrong: rooms %, active %, students %, answers %, quizzes %',
      o.rooms_total, o.active_30d, o.students_total, o.answers_total, o.quizzes_total;
  end if;

  select * into b from public.admin_teachers() t where t.user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  if b.rooms <> 1 or b.students <> 2 or b.quizzes <> 1 or b.suspended or b.is_admin then
    raise exception 'B''s row wrong: rooms %, students %, quizzes %, suspended %, admin %',
      b.rooms, b.students, b.quizzes, b.suspended, b.is_admin;
  end if;

  select count(*), max(signups) filter (where day = current_date) into n, today from public.admin_signups(30);
  if n <> 30 or today <> 4 then raise exception 'signups: % days, % today', n, today; end if;
  reset role;

  -- Structural: nothing the teacher list returns could carry a student's name.
  select count(*) into n from information_schema.parameters
  where specific_name like 'admin_teachers%' and parameter_mode = 'OUT'
    and parameter_name in ('name', 'player', 'players', 'nickname', 'answer', 'answers');
  if n <> 0 then raise exception 'admin_teachers returns a student-shaped column'; end if;

  raise notice 'ok  the admin sees every teacher''s counts, students only as numbers';
end $$;

-- Suspend and restore; and the two things an admin may not do.
do $$
declare refused boolean; banned timestamptz; sessions int;
begin
  perform set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', true);

  perform public.admin_suspend_teacher('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', true);
  select banned_until into banned from auth.users where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  select count(*) into sessions from auth.sessions where user_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  if banned is distinct from 'infinity' or sessions <> 0 then
    raise exception 'suspend: banned_until %, % sessions left', banned, sessions;
  end if;

  perform public.admin_suspend_teacher('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', false);
  select banned_until into banned from auth.users where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  if banned is not null then raise exception 'restore left banned_until at %', banned; end if;

  refused := false;
  begin
    perform public.admin_suspend_teacher('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
  exception when insufficient_privilege then refused := true;
  end;
  if not refused then raise exception 'an admin suspended themselves'; end if;

  refused := false;
  begin
    perform public.admin_delete_teacher('dddddddd-dddd-dddd-dddd-dddddddddddd');
  exception when insufficient_privilege then refused := true;
  end;
  if not refused then raise exception 'an admin deleted another admin'; end if;

  raise notice 'ok  suspend bans and signs out, restore lifts it; not on yourself, not on an admin';
end $$;

-- Delete takes B and everything B made, and nothing of C's.
do $$
declare n int;
begin
  perform set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', true);
  perform public.admin_delete_teacher('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

  select count(*) into n from auth.users where id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  if n <> 0 then raise exception 'B''s account is still there'; end if;
  select count(*) into n from public.quizzes where owner_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
  if n <> 0 then raise exception 'B''s quizzes are still there: %', n; end if;
  select count(*) into n from public.games;
  if n <> 0 then raise exception 'B''s room is still there'; end if;
  select count(*) into n from public.players;
  if n <> 0 then raise exception 'B''s students are still there: %', n; end if;
  select count(*) into n from public.answers;
  if n <> 0 then raise exception 'B''s students'' answers are still there: %', n; end if;

  select count(*) into n from public.quizzes where owner_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
  if n <> 1 then raise exception 'C''s quiz went too'; end if;

  raise notice 'ok  deleting a teacher removes their account, quizzes, rooms, students and answers, and nobody else''s';
end $$;
