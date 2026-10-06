-- Plans: Free and Teacher, and the limits that tell them apart.
--
-- The rule is the one the rest of the schema is built on: a browser can be made
-- to say anything, so a plan is never something the app tells the database. It
-- is a row the teacher cannot write, mirrored from Stripe by the webhook, and
-- every limit is checked here at the moment of the action. A teacher calling
-- these functions from the console meets the same limits as one using the app.
--
-- Two promises shape the rest. A room that is already open is never cut off: a
-- lapsed plan blocks the next room, not this lesson. And nothing is deleted when
-- a plan ends: the quizzes and reports stay, and paying again brings them back.

-- One row per teacher who has ever started to pay, or been given the plan.
-- `status` is Stripe's own word for the subscription, copied as it stands.
create table public.teacher_plans (
  user_id uuid primary key references auth.users (id) on delete cascade,
  stripe_customer_id text unique,
  stripe_subscription_id text,
  status text,
  billing_interval text,
  current_period_end timestamptz,
  cancel_at_period_end boolean not null default false,
  -- The Teacher plan without a subscription: the owner's own accounts, a beta
  -- tester, a favour. Set by SQL only; the webhook never touches it.
  comp boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.teacher_plans enable row level security;
-- No policies and no grants: the browser reads its own row through my_plan().
-- The webhook writes with the service role, which Supabase lets past both.
revoke all on public.teacher_plans from anon, authenticated;

-- Rooms opened per calendar month (UTC). A counter rather than a count of
-- `games`, because a teacher can delete a game and must not get the room back.
create table public.room_usage (
  user_id uuid not null references auth.users (id) on delete cascade,
  month date not null,
  rooms int not null default 0,
  primary key (user_id, month)
);

alter table public.room_usage enable row level security;
revoke all on public.room_usage from anon, authenticated;

-- What a room was opened with. A plan that lapses mid-lesson must not shrink a
-- room that is already running, so the cap is written down when it opens.
alter table public.games add column player_cap int;

-- ------------------------------------------------------------------ the plan --

-- The one place that decides. `past_due` still counts: Stripe is retrying the
-- card, and the teacher keeps the plan until Stripe gives up and cancels. How
-- long that takes is the retry schedule in the Stripe dashboard.
create function public.plan_of(p_user uuid)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case when exists (
    select 1 from public.teacher_plans t
    where t.user_id = p_user
      and (t.comp or coalesce(t.status in ('active', 'trialing', 'past_due'), false))
  ) then 'teacher' else 'free' end;
$$;

revoke execute on function public.plan_of(uuid) from public, anon, authenticated;

-- The numbers on the pricing page, and nowhere else. Null means no limit.
create function public.plan_limits(p_plan text)
returns table (quizzes int, rooms_per_month int, players_per_room int, report_days int, displays int)
language sql
immutable
set search_path = public, pg_temp
as $$
  select l.quizzes, l.rooms_per_month, l.players_per_room, l.report_days, l.displays
  from (values
    ('free',    3,         5,         15, 30,        1),
    ('teacher', null::int, null::int, 60, null::int, 10)
  ) as l (plan, quizzes, rooms_per_month, players_per_room, report_days, displays)
  where l.plan = case when p_plan = 'teacher' then 'teacher' else 'free' end;
$$;

revoke execute on function public.plan_limits(text) from public, anon, authenticated;

-- A teacher's own plan, limits and how much of them is used: everything the
-- Plan & billing sheet shows. It says nothing about anyone else.
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
  rooms_this_month int,
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
         l.rooms_per_month,
         coalesce((select u.rooms from public.room_usage u
                    where u.user_id = auth.uid()
                      and u.month = date_trunc('month', now() at time zone 'utc')::date), 0),
         l.players_per_room,
         l.report_days,
         l.displays
  from public.plan_limits(v_plan) l
  left join public.teacher_plans t on t.user_id = auth.uid();
end;
$$;

revoke execute on function public.my_plan() from public, anon;
grant execute on function public.my_plan() to authenticated;

-- ------------------------------------------------------------------- quizzes --

-- Quizzes are inserted straight into the table by the editor, and by the two
-- copying functions, so the limit is a trigger: one place every route passes.
-- Un-archiving counts as adding, or archive-create-restore would walk past it.
create function public.enforce_quiz_limit()
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

  -- One at a time per teacher, so a burst of inserts cannot all see "two so far".
  perform pg_advisory_xact_lock(hashtextextended('blurt:quizzes:' || new.owner_id::text, 0));

  if (select count(*) from public.quizzes z
       where z.owner_id = new.owner_id and z.archived_at is null and z.id <> new.id) >= v_limit then
    raise exception 'Your free plan includes % quizzes. Upgrade to add more.', v_limit
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

revoke execute on function public.enforce_quiz_limit() from public, anon, authenticated;

create trigger quizzes_plan_limit
  before insert or update of archived_at, owner_id on public.quizzes
  for each row execute function public.enforce_quiz_limit();

-- --------------------------------------------------------------------- rooms --

-- As 0024, plus the plan: the month's rooms are counted, and the room's size is
-- written on it as it opens.
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
  v_month constant date := date_trunc('month', now() at time zone 'utc')::date;
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

  -- Holding this row is what makes the count exact: two rooms opened at the
  -- same instant take turns here.
  insert into public.room_usage (user_id, month) values (auth.uid(), v_month)
  on conflict do nothing;
  select u.rooms into v_used from public.room_usage u
  where u.user_id = auth.uid() and u.month = v_month
  for update;

  if v_limits.rooms_per_month is not null and v_used >= v_limits.rooms_per_month then
    raise exception 'Your free plan includes % rooms a month, and this month''s are used. Upgrade to open more.',
      v_limits.rooms_per_month using errcode = 'check_violation';
  end if;

  update public.room_usage u set rooms = u.rooms + 1
  where u.user_id = auth.uid() and u.month = v_month;

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

-- As 0016, with the room's size coming from the plan instead of a constant.
-- The larger of what the room opened with and what its teacher has now: a plan
-- that lapses mid-lesson changes nothing, and one bought because the room
-- filled up lets the sixteenth student in without opening a new room.
create or replace function public.join_game(p_code text, p_name text)
returns table (player_id uuid, player_token uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_player public.players;
  v_token uuid;
  v_count int;
  v_room_cap int;
begin
  select * into v_game from public.games where code = upper(trim(p_code));
  if not found then
    raise exception 'no such room' using errcode = 'no_data_found';
  end if;

  if v_game.closed_at is not null then
    raise exception 'that room has closed' using errcode = 'check_violation';
  end if;

  if v_game.phase = 'final' then
    raise exception 'that game has finished' using errcode = 'check_violation';
  end if;

  if v_game.phase <> 'lobby' and not v_game.allow_late_join then
    raise exception 'that game has already started' using errcode = 'check_violation';
  end if;

  -- Rooms from before plans carry no cap and keep the old sixty.
  select greatest(coalesce(v_game.player_cap, 60), l.players_per_room) into v_room_cap
  from public.plan_limits(public.plan_of(v_game.owner_id)) l;

  select count(*) into v_count from public.players where game_id = v_game.id;
  if v_count >= v_room_cap then
    raise exception 'that room is full' using errcode = 'check_violation';
  end if;

  -- Deliberately vague. Saying which word tripped it is a hint about what to
  -- try next.
  if not public.name_is_clean(p_name) then
    raise exception 'pick a different name' using errcode = 'check_violation';
  end if;

  insert into public.players (game_id, name) values (v_game.id, trim(p_name))
  returning * into v_player;

  insert into public.player_secrets (player_id) values (v_player.id)
  returning player_secrets.token into v_token;

  return query select v_player.id, v_token;
exception
  when unique_violation then
    raise exception 'someone in this room already has that name'
      using errcode = 'unique_violation';
end;
$$;

grant execute on function public.join_game(text, text) to anon, authenticated;

-- ------------------------------------------------------------------ displays --

-- As 0029, with the count coming from the plan. Displays paired while on the
-- Teacher plan keep working afterwards; it is the next one that is refused.
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
      raise exception 'Your free plan includes % paired display. Upgrade to pair more.', v_limit
        using errcode = 'check_violation';
    end if;
    raise exception 'ten displays is already more rooms than anyone teaches in';
  end if;

  insert into public.walls (owner_id, label) values (auth.uid(), left(v_label, 40))
  returning id into v_id;

  return query select v_id, left(v_label, 40);
end;
$$;

grant execute on function public.create_wall(text) to authenticated;

-- ------------------------------------------------------------------- reports --

-- How far back a plan reads. Older games are hidden, not deleted: they are
-- there again the day the teacher upgrades, and delete_game still reaches them.
create function public.assert_report_open(p_played_at timestamptz)
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
    raise exception 'Your free plan shows reports from the last % days. Upgrade to open older ones.', v_days
      using errcode = 'check_violation';
  end if;
end;
$$;

revoke execute on function public.assert_report_open(timestamptz) from public, anon, authenticated;

-- As 0025, leaving out what the plan does not reach.
create or replace function public.my_games(p_limit int default 50)
returns table (
  game_id uuid,
  code text,
  played_at timestamptz,
  quiz_title text,
  finished boolean,
  players int,
  questions_asked int,
  questions_total int,
  top_name text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_days int;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;
  select l.report_days into v_days from public.plan_limits(public.plan_of(auth.uid())) l;

  return query
  select g.id,
         g.code,
         g.created_at,
         z.title,
         g.phase = 'final',
         (select count(*)::int from public.players p where p.game_id = g.id),
         (g.question_index + 1),
         (select count(*)::int from public.game_questions q where q.game_id = g.id),
         (select p.name from public.players p where p.game_id = g.id
          order by p.score desc, p.joined_at asc limit 1)
  from public.games g
  join public.quizzes z on z.id = g.quiz_id
  where g.owner_id = auth.uid() and g.question_index >= 0
    and (v_days is null or g.created_at >= now() - make_interval(days => v_days))
  order by g.created_at desc
  limit greatest(1, least(p_limit, 200));
end;
$$;

grant execute on function public.my_games(int) to authenticated;

-- How many reports the plan is hiding, so the page can say so instead of
-- looking as if they were lost.
create function public.my_hidden_games()
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select count(*)::int
  from public.games g, public.plan_limits(public.plan_of(auth.uid())) l
  where g.owner_id = auth.uid() and g.question_index >= 0
    and l.report_days is not null
    and g.created_at < now() - make_interval(days => l.report_days);
$$;

revoke execute on function public.my_hidden_games() from public, anon;
grant execute on function public.my_hidden_games() to authenticated;

-- As 0025.
create or replace function public.game_summary(p_game_id uuid)
returns table (
  code text,
  played_at timestamptz,
  quiz_title text,
  finished boolean,
  players int,
  questions_asked int,
  questions_total int,
  blurt_enabled boolean,
  streak_bonus boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_played_at timestamptz;
begin
  select g.created_at into v_played_at from public.games g
  where g.id = p_game_id and g.owner_id = auth.uid();

  if not found then
    raise exception 'that is not your game' using errcode = 'insufficient_privilege';
  end if;
  perform public.assert_report_open(v_played_at);

  return query
  select g.code, g.created_at, z.title, g.phase = 'final',
         (select count(*)::int from public.players p where p.game_id = g.id),
         (g.question_index + 1),
         (select count(*)::int from public.game_questions q where q.game_id = g.id),
         g.blurt_enabled, g.streak_bonus
  from public.games g
  join public.quizzes z on z.id = g.quiz_id
  where g.id = p_game_id and g.owner_id = auth.uid();
end;
$$;

grant execute on function public.game_summary(uuid) to authenticated;

-- As 0026, with the plan check after the ownership check.
create or replace function public.game_report(p_game_id uuid)
returns table (
  q_position int,
  q_kind text,
  q_text text,
  q_answer text,
  answered int,
  correct int,
  percent_correct int,
  median_ms int,
  common_wrong text,
  common_wrong_count int,
  blurter text,
  blurt_correct boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select g.* into v_game from public.games g
  where g.id = p_game_id and g.owner_id = auth.uid();

  if not found then
    raise exception 'that is not your game' using errcode = 'insufficient_privilege';
  end if;
  perform public.assert_report_open(v_game.created_at);

  return query
  with asked as (
    select * from public.game_questions q
    where q.game_id = p_game_id and q.position <= v_game.question_index
  ),
  mine as (
    -- Every later clause reads from here rather than from `answers`, so there is
    -- one place the game is filtered instead of three places to forget it.
    select a.* from public.answers a where a.game_id = p_game_id
  ),
  tallied as (
    select a.question_index,
           count(*) filter (where a.correct)::int as right_answers,
           percentile_cont(0.5) within group (order by a.ms_elapsed)
             filter (where not a.blurted) as median,
           count(*)::int as total
    from mine a
    group by a.question_index
  ),
  wrong as (
    select distinct on (a.question_index)
           a.question_index,
           coalesce(a.answer_text, q.choices[a.choice + 1]) as label,
           count(*)::int as hits
    from mine a
    join asked q on q.position = a.question_index
    where not a.correct and not a.blurted
    group by a.question_index, coalesce(a.answer_text, q.choices[a.choice + 1])
    order by a.question_index, count(*) desc, 2
  ),
  claimed as (
    select distinct on (a.question_index) a.question_index, p.name, a.correct
    from mine a
    join public.players p on p.id = a.player_id
    where a.blurted
    order by a.question_index, a.created_at
  )
  select q.position,
         q.kind,
         q.text,
         coalesce(q.accepted[1], q.choices[q.correct_index + 1]),
         coalesce(t.total, 0),
         coalesce(t.right_answers, 0),
         case when coalesce(t.total, 0) = 0 then 0
              else round(100.0 * t.right_answers / t.total)::int end,
         coalesce(t.median, 0)::int,
         w.label,
         w.hits,
         c.name,
         c.correct
  from asked q
  left join tallied t on t.question_index = q.position
  left join wrong w on w.question_index = q.position
  left join claimed c on c.question_index = q.position
  order by case when coalesce(t.total, 0) = 0 then 0
                else round(100.0 * t.right_answers / t.total) end asc,
           q.position asc;
end;
$$;

grant execute on function public.game_report(uuid) to authenticated;

-- As 0025, likewise.
create or replace function public.game_players(p_game_id uuid)
returns table (
  player_id uuid,
  player_name text,
  score int,
  place int,
  answered int,
  correct int,
  best_streak int,
  blurt_wins int,
  blurt_misses int,
  avg_ms int,
  missed int[]
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select g.* into v_game from public.games g
  where g.id = p_game_id and g.owner_id = auth.uid();

  if not found then
    raise exception 'that is not your game' using errcode = 'insufficient_privilege';
  end if;
  perform public.assert_report_open(v_game.created_at);

  return query
  with per_question as (
    select a.player_id, a.question_index,
           bool_or(a.correct) as correct,
           bool_or(a.blurted and a.correct) as blurt_win,
           bool_or(a.blurted and not a.correct) as blurt_miss,
           min(a.ms_elapsed) filter (where not a.blurted) as ms
    from public.answers a
    where a.game_id = p_game_id
    group by a.player_id, a.question_index
  ),
  -- Longest run of right answers: number each question, subtract a running count
  -- of the wrong ones, and every unbroken run shares a value to group on.
  -- Every column qualified: `player_id` is also an OUT parameter of this
  -- function, and an unqualified reference is ambiguous between the two.
  runs as (
    select pq.player_id, pq.question_index, pq.correct,
           pq.question_index - count(*) filter (where pq.correct)
             over (partition by pq.player_id order by pq.question_index) as run_id
    from per_question pq
  ),
  streaks as (
    select s.player_id, max(s.len)::int as best
    from (
      select r.player_id, r.run_id, count(*) as len
      from runs r where r.correct
      group by r.player_id, r.run_id
    ) s
    group by s.player_id
  ),
  agg as (
    select q.player_id,
           count(*)::int as answered,
           count(*) filter (where q.correct)::int as correct,
           count(*) filter (where q.blurt_win)::int as blurt_wins,
           count(*) filter (where q.blurt_miss)::int as blurt_misses,
           coalesce(avg(q.ms), 0)::int as avg_ms,
           coalesce(array_agg(q.question_index order by q.question_index)
                    filter (where not q.correct), '{}') as missed
    from per_question q
    group by q.player_id
  )
  select p.id, p.name, p.score,
         rank() over (order by p.score desc)::int,
         coalesce(a.answered, 0), coalesce(a.correct, 0),
         coalesce(s.best, 0), coalesce(a.blurt_wins, 0), coalesce(a.blurt_misses, 0),
         coalesce(a.avg_ms, 0), coalesce(a.missed, '{}')
  from public.players p
  left join agg a on a.player_id = p.id
  left join streaks s on s.player_id = p.id
  where p.game_id = p_game_id
  order by p.score desc, p.joined_at asc;
end;
$$;

grant execute on function public.game_players(uuid) to authenticated;

-- --------------------------------------------------------------------- admin --

-- As 0033, with what each teacher is paying. The return type changes, so the
-- old one is dropped rather than replaced.
drop function public.admin_teachers();

create function public.admin_teachers()
returns table (
  user_id uuid,
  email text,
  signed_up_at timestamptz,
  confirmed_at timestamptz,
  last_sign_in_at timestamptz,
  suspended boolean,
  is_admin boolean,
  quizzes int,
  rooms int,
  students int,
  last_room_at timestamptz,
  plan text,
  plan_status text,
  plan_comp boolean,
  stripe_customer_id text
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_platform_admin();
  return query
  select
    u.id,
    u.email::text,
    u.created_at,
    u.email_confirmed_at,
    u.last_sign_in_at,
    coalesce(u.banned_until > now(), false),
    exists (select 1 from public.platform_admins a where a.user_id = u.id),
    (select count(*)::int from public.quizzes z where z.owner_id = u.id and z.archived_at is null),
    (select count(*)::int from public.games g where g.owner_id = u.id),
    (select count(*)::int from public.players p join public.games g on g.id = p.game_id where g.owner_id = u.id),
    (select max(g.created_at) from public.games g where g.owner_id = u.id),
    public.plan_of(u.id),
    t.status,
    coalesce(t.comp, false),
    t.stripe_customer_id
  from auth.users u
  left join public.teacher_plans t on t.user_id = u.id
  order by u.created_at desc;
end;
$$;

revoke execute on function public.admin_teachers() from public, anon;
grant execute on function public.admin_teachers() to authenticated;

-- As 0033, but not while Stripe is still charging them. Deleting the account
-- takes the plan row with it, and the subscription would go on billing a card
-- for an account that no longer exists. The database cannot reach Stripe, so it
-- refuses until the subscription has been cancelled there.
create or replace function public.admin_delete_teacher(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_platform_admin();
  perform public.assert_admin_target(p_user);

  if exists (
    select 1 from public.teacher_plans t
    where t.user_id = p_user and coalesce(t.status in ('active', 'trialing', 'past_due'), false)
  ) then
    raise exception 'they have a live subscription: cancel it in Stripe first'
      using errcode = 'check_violation';
  end if;

  delete from public.games g where g.owner_id = p_user;
  -- Rooms from before games had an owner still point at the quiz they ran.
  delete from public.games g using public.quizzes z where g.quiz_id = z.id and z.owner_id = p_user;
  delete from auth.users u where u.id = p_user;
end;
$$;

revoke execute on function public.admin_delete_teacher(uuid) from public, anon;
grant execute on function public.admin_delete_teacher(uuid) to authenticated;
