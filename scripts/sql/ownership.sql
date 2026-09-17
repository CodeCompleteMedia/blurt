-- Who may host, read and copy a quiz.
--
-- This closed a hole open since Phase 1: before ownership existed, anyone with
-- the anon key could open a private room on any quiz and then read the answer
-- key off the host view.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'teacher@school'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'student-with-an-account@school');

do $$
declare
  v_template uuid := '11111111-1111-1111-1111-111111111111';
  v_mine uuid;
  g record;
  n int;
  refused boolean;
begin
  -- A student holding only the anon key cannot open a room at all.
  perform set_config('request.jwt.claims', '', false);
  refused := false;
  begin perform public.create_game(v_template);
  exception when others then refused := true; end;
  if not refused then raise exception 'a signed-out client opened a room'; end if;

  -- Nor can a signed-in teacher host the ownerless template: it exists to be
  -- copied, not played, or every teacher would share one quiz.
  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);
  refused := false;
  begin perform public.create_game(v_template);
  exception when others then refused := true; end;
  if not refused then raise exception 'the shared template was hosted directly'; end if;

  -- They get their own copy, and can host that.
  v_mine := public.copy_sample_quiz();
  select count(*) into n from public.questions where quiz_id = v_mine;
  if n <> 5 then raise exception 'the copy has % questions, expected 5', n; end if;

  select * into g from public.create_game(v_mine);
  if g.code is null then raise exception 'hosting my own copy did not open a room'; end if;

  -- A student who makes an account still cannot host or copy the teacher's quiz.
  perform set_config('request.jwt.claims',
    '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false);
  refused := false;
  begin perform public.create_game(v_mine);
  exception when others then refused := true; end;
  if not refused then raise exception 'a student account hosted the teacher''s quiz'; end if;

  refused := false;
  begin perform public.duplicate_quiz(v_mine);
  exception when others then refused := true; end;
  if not refused then raise exception 'a student account copied the teacher''s quiz'; end if;

  perform set_config('blurt.mine', v_mine::text, false);
  raise notice 'ok  the template cannot be hosted, only copied; a copy is hostable only by its owner';
end $$;

-- Row level security, seen as each of them: the question text and the correct
-- answers live in these tables, so what a student's own account can read is the
-- whole ball game.
do $$
declare n_quizzes int; n_questions int; refused boolean; ok_swap boolean;
begin
  set local role authenticated;

  perform set_config('request.jwt.claims',
    '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false);
  select count(*) into n_quizzes from public.quizzes;
  select count(*) into n_questions from public.questions;
  if n_quizzes <> 0 or n_questions <> 0 then
    raise exception 'a student account can read % quizzes and % questions', n_quizzes, n_questions;
  end if;

  perform set_config('request.jwt.claims',
    '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);
  select count(*) into n_quizzes from public.quizzes;
  select count(*) into n_questions from public.questions;
  if n_quizzes <> 1 or n_questions <> 5 then
    raise exception 'the teacher sees % quizzes and % questions, expected 1 and 5',
      n_quizzes, n_questions;
  end if;

  -- And cannot plant a row in someone else's name.
  refused := false;
  begin
    insert into public.quizzes (title, owner_id)
    values ('planted', 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
  exception when others then refused := true; end;
  if not refused then raise exception 'a quiz was written into another user''s name'; end if;

  -- Swapping two positions in one statement must not trip the unique index
  -- halfway through; that is what the deferrable constraint is for.
  update public.questions q
     set position = case q.position when 0 then 1 when 1 then 0 else q.position end
   where q.quiz_id = current_setting('blurt.mine')::uuid;

  if (select array_agg(q.position order by q.position) from public.questions q
      where q.quiz_id = current_setting('blurt.mine')::uuid) <> array[0,1,2,3,4] then
    raise exception 'positions are no longer 0..4 after an in-place swap';
  end if;

  reset role;
  raise notice 'ok  a student account reads nothing; the owner reads only their own';
end $$;

do $$
declare t text; n int;
begin
  -- No select grant at all is the outcome here, which is stronger than a grant
  -- that RLS filters to nothing. Either passes; rows coming back does not.
  foreach t in array array['quizzes', 'questions'] loop
    begin
      set local role anon;
      execute format('select count(*) from public.%I', t) into n;
      reset role;
      if n <> 0 then
        raise exception 'the anon key reads % rows of %', n, t;
      end if;
    exception when insufficient_privilege then
      reset role;
    end;
  end loop;
  raise notice 'ok  the anon key is refused both quizzes and questions outright';
end $$;
