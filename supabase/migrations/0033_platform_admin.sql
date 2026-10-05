-- The platform admin: one person (or a few) who can see across every teacher.
--
-- Everything else in this schema answers one question: "is this yours?" This
-- adds a second, narrower one: "are you on the admin list?" The list is a table
-- no client can read or write; the only way onto it is SQL run by the project
-- owner. Every admin function checks it first, on the server, so an admin page
-- in the browser is a view onto these functions and nothing more.
--
-- Student data stays out of reach even for an admin: these functions count
-- players and answers, and never return a name, a nickname or an answer.

create table public.platform_admins (
  user_id uuid primary key references auth.users (id) on delete cascade,
  added_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;
revoke all on public.platform_admins from anon, authenticated;

-- Anyone signed in may ask about themselves, so the app knows whether to show
-- the Admin link. It says nothing about anyone else.
create function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (select 1 from public.platform_admins a where a.user_id = auth.uid());
$$;

revoke execute on function public.is_platform_admin() from public, anon;
grant execute on function public.is_platform_admin() to authenticated;

-- The gate every admin function starts with. Internal: nobody calls it directly.
create function public.assert_platform_admin()
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (select 1 from public.platform_admins a where a.user_id = auth.uid()) then
    raise exception 'admins only' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

revoke execute on function public.assert_platform_admin() from public, anon, authenticated;

-- ------------------------------------------------------------------ reads --

-- The numbers at the top of the page. "Active" means hosted a room.
create function public.admin_overview()
returns table (
  teachers int,
  confirmed int,
  signups_7d int,
  signups_30d int,
  active_7d int,
  active_30d int,
  rooms_7d int,
  rooms_30d int,
  rooms_total int,
  students_7d int,
  students_30d int,
  students_total int,
  answers_total int,
  quizzes_total int
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
    (select count(*)::int from auth.users),
    (select count(*)::int from auth.users u where u.email_confirmed_at is not null),
    (select count(*)::int from auth.users u where u.created_at > now() - interval '7 days'),
    (select count(*)::int from auth.users u where u.created_at > now() - interval '30 days'),
    (select count(distinct g.owner_id)::int from public.games g where g.created_at > now() - interval '7 days'),
    (select count(distinct g.owner_id)::int from public.games g where g.created_at > now() - interval '30 days'),
    (select count(*)::int from public.games g where g.created_at > now() - interval '7 days'),
    (select count(*)::int from public.games g where g.created_at > now() - interval '30 days'),
    (select count(*)::int from public.games),
    (select count(*)::int from public.players p where p.joined_at > now() - interval '7 days'),
    (select count(*)::int from public.players p where p.joined_at > now() - interval '30 days'),
    (select count(*)::int from public.players),
    (select count(*)::int from public.answers),
    -- Teachers' quizzes; the built-in sample belongs to nobody.
    (select count(*)::int from public.quizzes z where z.archived_at is null and z.owner_id is not null);
end;
$$;

revoke execute on function public.admin_overview() from public, anon;
grant execute on function public.admin_overview() to authenticated;

-- New teachers per day, oldest first, with the empty days included so a chart
-- of it has no gaps to misread.
create function public.admin_signups(p_days int default 30)
returns table (day date, signups int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_days int := least(greatest(coalesce(p_days, 30), 1), 366);
begin
  perform public.assert_platform_admin();
  return query
  select d::date, count(u.id)::int
  from generate_series(current_date - (v_days - 1), current_date, interval '1 day') d
  left join auth.users u on u.created_at::date = d::date
  group by d
  order by d;
end;
$$;

revoke execute on function public.admin_signups(int) from public, anon;
grant execute on function public.admin_signups(int) to authenticated;

-- One row per teacher. Students are a count, never a list.
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
  last_room_at timestamptz
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
    (select max(g.created_at) from public.games g where g.owner_id = u.id)
  from auth.users u
  order by u.created_at desc;
end;
$$;

revoke execute on function public.admin_teachers() from public, anon;
grant execute on function public.admin_teachers() to authenticated;

-- ---------------------------------------------------------------- actions --

-- Who an action may touch: a real teacher, not yourself, not another admin. An
-- admin locking out the other admins, or themselves, is not something to allow
-- by a stray click.
create function public.assert_admin_target(p_user uuid)
returns void
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if p_user is null or not exists (select 1 from auth.users u where u.id = p_user) then
    raise exception 'no such teacher' using errcode = 'no_data_found';
  end if;
  if p_user = auth.uid() then
    raise exception 'not on your own account' using errcode = 'insufficient_privilege';
  end if;
  if exists (select 1 from public.platform_admins a where a.user_id = p_user) then
    raise exception 'not on another admin' using errcode = 'insufficient_privilege';
  end if;
end;
$$;

revoke execute on function public.assert_admin_target(uuid) from public, anon, authenticated;

-- Suspend or restore. Suspending sets Supabase Auth's own ban, which blocks
-- signing in and refreshing a session, and ends the sessions they have now. An
-- access token already issued lives out its remaining hour at most.
create function public.admin_suspend_teacher(p_user uuid, p_suspend boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_platform_admin();
  perform public.assert_admin_target(p_user);

  if coalesce(p_suspend, true) then
    update auth.users set banned_until = 'infinity' where id = p_user;
    delete from auth.sessions where user_id = p_user;
  else
    update auth.users set banned_until = null where id = p_user;
  end if;
end;
$$;

revoke execute on function public.admin_suspend_teacher(uuid, boolean) from public, anon;
grant execute on function public.admin_suspend_teacher(uuid, boolean) to authenticated;

-- Delete a teacher and everything they made. Games go first: they point at
-- quizzes without a cascade (a report needs its quiz), so while any game exists
-- the account cannot go. Deleting a game takes its players, answers and secrets
-- with it. Then the account, which takes quizzes, questions, displays and
-- sessions. Question images in storage are not removed here: Supabase deletes
-- stored files through its storage API, not through SQL.
create function public.admin_delete_teacher(p_user uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.assert_platform_admin();
  perform public.assert_admin_target(p_user);

  delete from public.games g where g.owner_id = p_user;
  -- Rooms from before games had an owner still point at the quiz they ran.
  delete from public.games g using public.quizzes z where g.quiz_id = z.id and z.owner_id = p_user;
  delete from auth.users u where u.id = p_user;
end;
$$;

revoke execute on function public.admin_delete_teacher(uuid) from public, anon;
grant execute on function public.admin_delete_teacher(uuid) to authenticated;
