-- Two ways round a limit, closed. Both came out of a security review of 0034
-- and 0035, and neither needs anything but the public key and patience.
--
-- 1. A plan that never ended. The database believed "active" until Stripe's
--    webhook said otherwise, so a teacher who cancelled while the webhook was
--    not arriving kept the plan for good. A subscription now counts only until
--    the end of the period Stripe last reported, plus a few days. The app also
--    asks the server to re-read Stripe when a row is a day old (my_plan's
--    synced_at), which is what keeps a teacher who is still paying from being
--    dropped if a renewal's webhook goes missing.
--
-- 2. A closed waiting room that could still be started. Free has one waiting
--    room at a time, and opening another closes the first, but nothing stopped
--    the first from being started afterwards. Seat a class in each and that is
--    as many games as you like.
--
-- Also here: the limit messages say "the Free plan", as the app does.

-- ------------------------------------------------------------------ the plan --

-- As 0034, and not past the paid period. Three days is for a webhook that is
-- late, not a way to stretch a month. A row with no period at all is believed:
-- only the server writes these, and failing shut on a shape Stripe changed
-- would lock out people who are paying. `comp` has no period and needs none.
create or replace function public.plan_of(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when exists (
    select 1 from public.teacher_plans t
    where t.user_id = p_user
      and (
        t.comp
        or (
          coalesce(t.status in ('active', 'trialing', 'past_due'), false)
          and (t.current_period_end is null or t.current_period_end > now() - interval '3 days')
        )
      )
  ) then 'teacher' else 'free' end;
$$;

-- As 0035, with when the row was last copied from Stripe. The return type
-- changes, so the old one is dropped.
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
  display_limit int,
  synced_at timestamptz
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
         l.displays,
         t.updated_at
  from public.plan_limits(v_plan) l
  left join public.teacher_plans t on t.user_id = auth.uid();
end;
$$;

revoke execute on function public.my_plan() from public, anon;
grant execute on function public.my_plan() to authenticated;

-- ------------------------------------------------------- starting a room ---

-- A trigger for the same reason the count is one (0035): whichever function
-- asks the first question, a closed room is refused. Only the step out of the
-- lobby is checked, so a game already under way is never touched.
create function public.refuse_closed_start()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if old.question_index < 0 and new.question_index >= 0 and old.closed_at is not null then
    raise exception 'that room has closed' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke execute on function public.refuse_closed_start() from public, anon, authenticated;

create trigger games_refuse_closed_start
  before update of question_index on public.games
  for each row execute function public.refuse_closed_start();

-- ------------------------------------------------------------ the wording ---
-- The four functions below are unchanged from where they were last defined
-- except for one sentence each.

-- As 0035.
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
      raise exception 'You have played the % games the Free plan includes. Upgrade to play more.',
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

-- As 0035.
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
    raise exception 'The Free plan includes the sample quiz and one of your own. Upgrade to add more.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

-- As 0034.
create or replace function public.create_wall(p_label text)
returns table (wall_id uuid, label text)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_label text := btrim(coalesce(p_label, ''));
  v_id uuid;
  v_plan text;
  v_limit int;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;
  if length(v_label) = 0 then
    raise exception 'give the display a name you will recognise';
  end if;

  v_plan := public.plan_of(auth.uid());
  select l.displays into v_limit from public.plan_limits(v_plan) l;
  perform pg_advisory_xact_lock(hashtextextended('blurt:walls:' || auth.uid()::text, 0));

  if (select count(*) from public.walls w where w.owner_id = auth.uid()) >= v_limit then
    if v_plan = 'free' then
      raise exception 'The Free plan includes % paired display. Upgrade to pair more.', v_limit
        using errcode = 'check_violation';
    end if;
    raise exception 'ten displays is already more rooms than anyone teaches in';
  end if;

  insert into public.walls (owner_id, label) values (auth.uid(), left(v_label, 40))
  returning id into v_id;

  return query select v_id, left(v_label, 40);
end;
$$;

-- As 0034. No plan uses it today.
create or replace function public.assert_report_open(p_played_at timestamptz)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_days int;
begin
  select l.report_days into v_days from public.plan_limits(public.plan_of(auth.uid())) l;
  if v_days is not null and p_played_at < now() - make_interval(days => v_days) then
    raise exception 'The Free plan shows reports from the last % days. Upgrade to open older ones.', v_days
      using errcode = 'check_violation';
  end if;
end;
$$;

