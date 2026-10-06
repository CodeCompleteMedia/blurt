-- Free becomes a way to see the game in action, not an account to live on.
--
-- Three games, ever, with a whole class in each: up to forty students, the
-- sample quiz and one of the teacher's own, and the report afterwards kept. The
-- fourth game needs the Teacher plan. Nothing is taken away at that point: the
-- quizzes stay editable and the three reports stay readable.
--
-- With so few, what counts as one matters. A game counts when its first
-- question is asked, not when its room is opened, so opening a room to look
-- around, or to check the projector, costs nothing. The tally is room_usage,
-- which a deleted game does not come off.

-- The return type changes (rooms_per_month becomes rooms_total), so this is a
-- drop and not a replace.
drop function public.plan_limits(text);

create function public.plan_limits(p_plan text)
returns table (quizzes int, rooms_total int, players_per_room int, report_days int, displays int)
language sql
immutable
set search_path = public, pg_temp
as $$
  select l.quizzes, l.rooms_total, l.players_per_room, l.report_days, l.displays
  from (values
    ('free',    2,         3,         40, null::int, 1),
    ('teacher', null::int, null::int, 60, null::int, 10)
  ) as l (plan, quizzes, rooms_total, players_per_room, report_days, displays)
  where l.plan = case when p_plan = 'teacher' then 'teacher' else 'free' end;
$$;

revoke execute on function public.plan_limits(text) from public, anon, authenticated;

-- ------------------------------------------------------- counting a game ---

-- The moment a room leaves the lobby. A trigger, so that whichever function
-- asks the first question, now or in a later migration, it is counted once.
create function public.count_started_room()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.owner_id is not null and old.question_index < 0 and new.question_index >= 0 then
    insert into public.room_usage (user_id, month, rooms)
    values (new.owner_id, date_trunc('month', now() at time zone 'utc')::date, 1)
    on conflict (user_id, month) do update set rooms = public.room_usage.rooms + 1;
  end if;
  return null;
end;
$$;

revoke execute on function public.count_started_room() from public, anon, authenticated;

create trigger games_count_started
  after update of question_index on public.games
  for each row execute function public.count_started_room();

-- As 0034, with the allowance counted over the life of the account, and at the
-- first question instead of here.
create or replace function public.create_game(p_quiz_id uuid)
returns table (code text, host_token uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPRSTUVWXYZ23456789';
  v_code text;
  v_game public.games;
  v_host_token uuid;
  v_limits record;
  v_used int;
begin
  if auth.uid() is null or not exists (
    select 1 from public.quizzes z
    where z.id = p_quiz_id and z.owner_id = auth.uid() and z.archived_at is null
  ) then
    raise exception 'that is not your quiz' using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.questions q where q.quiz_id = p_quiz_id) then
    raise exception 'that quiz has no questions yet' using errcode = 'check_violation';
  end if;

  select * into v_limits from public.plan_limits(public.plan_of(auth.uid()));

  if v_limits.rooms_total is not null then
    -- One at a time per teacher, so two rooms opened at once take turns here.
    perform pg_advisory_xact_lock(hashtextextended('blurt:rooms:' || auth.uid()::text, 0));

    select coalesce(sum(u.rooms), 0) into v_used from public.room_usage u where u.user_id = auth.uid();
    if v_used >= v_limits.rooms_total then
      raise exception 'You have played the % games the free plan includes. Upgrade to play more.',
        v_limits.rooms_total using errcode = 'check_violation';
    end if;

    -- One waiting room at a time. Counting at the first question would
    -- otherwise let someone open a hundred lobbies while under the limit and
    -- start them at leisure. Nobody is cut off by this: a room that has asked
    -- a question is not a lobby.
    update public.games g set closed_at = now()
    where g.owner_id = auth.uid() and g.question_index < 0 and g.closed_at is null;
  end if;

  loop
    v_code := (
      select string_agg(substr(v_alphabet, floor(random() * length(v_alphabet))::int + 1, 1), '')
      from generate_series(1, 5)
    );
    exit when not exists (select 1 from public.games g where g.code = v_code);
  end loop;

  insert into public.games (code, quiz_id, owner_id, player_cap)
  values (v_code, p_quiz_id, auth.uid(), v_limits.players_per_room)
  returning * into v_game;

  insert into public.game_questions
    (game_id, position, kind, text, choices, correct_index, accepted,
     seconds, recall_seconds, blurt_enabled, image_path)
  select v_game.id, q.position, q.kind, q.text, q.choices, q.correct_index, q.accepted,
         coalesce(q.seconds, z.default_seconds), q.recall_seconds, q.blurt_enabled, q.image_path
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = p_quiz_id;

  insert into public.game_secrets (game_id) values (v_game.id)
  returning game_secrets.host_token into v_host_token;

  return query select v_game.code, v_host_token;
end;
$$;

grant execute on function public.create_game(uuid) to anon, authenticated;

-- ------------------------------------------------------------------ quizzes --

-- As 0034, saying the limit the way the pricing page does. It is a count of
-- two, not a rule about which two: a teacher who deletes the sample, or
-- rewrites it, has two quizzes of their own, and that is fine.
create or replace function public.enforce_quiz_limit()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_limit int;
begin
  -- The built-in sample belongs to nobody, and an archived quiz takes no room.
  if new.owner_id is null or new.archived_at is not null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.archived_at is null and old.owner_id is not distinct from new.owner_id then
    return new;
  end if;

  select l.quizzes into v_limit from public.plan_limits(public.plan_of(new.owner_id)) l;
  if v_limit is null then
    return new;
  end if;

  -- One at a time per teacher, so a burst of inserts cannot all see "one so far".
  perform pg_advisory_xact_lock(hashtextextended('blurt:quizzes:' || new.owner_id::text, 0));

  if (select count(*) from public.quizzes z
       where z.owner_id = new.owner_id and z.archived_at is null and z.id <> new.id) >= v_limit then
    raise exception 'The free plan includes the sample quiz and one of your own. Upgrade to add more.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- ------------------------------------------------------------- the teacher --

-- As 0034, reporting games played over the life of the account. The return
-- type changes, so the old one is dropped.
drop function public.my_plan();

create function public.my_plan()
returns table (
  plan text,
  status text,
  billing_interval text,
  current_period_end timestamptz,
  cancel_at_period_end boolean,
  comp boolean,
  has_customer boolean,
  quiz_limit int,
  quizzes int,
  room_limit int,
  rooms_used int,
  player_limit int,
  report_days int,
  display_limit int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_plan text;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;
  v_plan := public.plan_of(auth.uid());

  return query
  select v_plan,
         t.status,
         t.billing_interval,
         t.current_period_end,
         coalesce(t.cancel_at_period_end, false),
         coalesce(t.comp, false),
         t.stripe_customer_id is not null,
         l.quizzes,
         (select count(*)::int from public.quizzes z
           where z.owner_id = auth.uid() and z.archived_at is null),
         l.rooms_total,
         (select coalesce(sum(u.rooms), 0)::int from public.room_usage u where u.user_id = auth.uid()),
         l.players_per_room,
         l.report_days,
         l.displays
  from public.plan_limits(v_plan) l
  left join public.teacher_plans t on t.user_id = auth.uid();
end;
$$;

revoke execute on function public.my_plan() from public, anon;
grant execute on function public.my_plan() to authenticated;
