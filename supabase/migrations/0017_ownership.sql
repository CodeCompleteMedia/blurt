-- Who may host a quiz.
--
-- Every defence so far protects a room from its players. Nothing said who was
-- allowed to be the host — and the host can see the answers. So a student with
-- the anon key could open a private room on any quiz, become its "host", and walk
-- off with the answer key the night before. That has been true since the first
-- playable build; it only starts to matter now that quizzes are about to be worth
-- stealing.
--
-- Quizzes get an owner, and only the owner can host one, read it, or change it.
-- Accounts are Supabase Auth, which the project already has. Students never sign
-- in to anything: a seat token is still all a phone holds.

alter table public.quizzes
  add column owner_id uuid references auth.users (id) on delete cascade default auth.uid();

create index quizzes_by_owner on public.quizzes (owner_id);

-- Worth keeping from the start: the reports in a later phase will want "my past
-- games", and there is no honest way to backfill it.
alter table public.games
  add column owner_id uuid references auth.users (id) on delete set null;

-- ------------------------------------------------------------------ access ---

-- Titles were readable by anyone so the host screen could list them. The host
-- screen signs in now, and a list of quiz titles is itself a small leak.
drop policy if exists quizzes_readable on public.quizzes;
revoke all on public.quizzes from anon, authenticated;
revoke all on public.questions from anon, authenticated;

grant select, insert, update, delete on public.quizzes to authenticated;
grant select, insert, update, delete on public.questions to authenticated;

-- A teacher is trusted with their own content, so the editor writes to these
-- tables directly and row level security does the fencing. Students are not in
-- this picture at all: anon has no grant on either table.
create policy quizzes_owner on public.quizzes
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy questions_owner on public.questions
  for all to authenticated
  using (exists (select 1 from public.quizzes z where z.id = quiz_id and z.owner_id = auth.uid()))
  with check (exists (select 1 from public.quizzes z where z.id = quiz_id and z.owner_id = auth.uid()));

-- Reordering swaps positions, and a plain unique constraint is checked row by
-- row — so swapping 1 and 2 collides with itself halfway through. Deferrable
-- means the check waits for the end of the statement.
alter table public.questions drop constraint questions_quiz_id_position_key;
alter table public.questions
  add constraint questions_quiz_id_position_key unique (quiz_id, position) deferrable initially immediate;

-- ------------------------------------------------------------ create game ---

create or replace function public.create_game(p_quiz_id uuid)
returns table (code text, host_token uuid)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_code text;
  v_game public.games;
  v_host_token uuid;
begin
  -- The whole fix. One message for "not signed in", "no such quiz" and "someone
  -- else's quiz", so the error cannot be used to discover which quizzes exist.
  if auth.uid() is null or not exists (
    select 1 from public.quizzes z where z.id = p_quiz_id and z.owner_id = auth.uid()
  ) then
    raise exception 'that is not your quiz' using errcode = 'insufficient_privilege';
  end if;

  if not exists (select 1 from public.questions q where q.quiz_id = p_quiz_id) then
    raise exception 'that quiz has no questions yet' using errcode = 'check_violation';
  end if;

  loop
    v_code := (
      select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                               (random() * 31)::int + 1, 1), '')
      from generate_series(1, 5)
    );
    exit when not exists (select 1 from public.games g where g.code = v_code);
  end loop;

  insert into public.games (code, quiz_id, owner_id) values (v_code, p_quiz_id, auth.uid())
  returning * into v_game;

  insert into public.game_secrets (game_id) values (v_game.id)
  returning game_secrets.host_token into v_host_token;

  return query select v_game.code, v_host_token;
end;
$$;

-- Anon may still *call* it — and be refused by the check above, with a message
-- rather than a bare permission error.
grant execute on function public.create_game(uuid) to anon, authenticated;

-- ---------------------------------------------------------- a first quiz ---

-- The five starter questions stay in the database as a template nobody owns,
-- which also means nobody can host them. A new teacher gets their own copy, so
-- the first thing they see is a working quiz rather than an empty list.
create or replace function public.copy_sample_quiz()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_template constant uuid := '11111111-1111-1111-1111-111111111111';
  v_new uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  insert into public.quizzes (title, default_seconds, owner_id)
  select z.title, z.default_seconds, auth.uid() from public.quizzes z where z.id = v_template
  returning id into v_new;

  insert into public.questions (quiz_id, position, text, choices, correct_index, seconds, recall_seconds)
  select v_new, q.position, q.text, q.choices, q.correct_index, q.seconds, q.recall_seconds
  from public.questions q where q.quiz_id = v_template;

  return v_new;
end;
$$;

grant execute on function public.copy_sample_quiz() to authenticated;

-- Copying inside the database rather than read-then-insert from the browser, so
-- a forty-question quiz duplicates in one round trip and cannot half-finish.
create or replace function public.duplicate_quiz(p_quiz_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_new uuid;
begin
  if auth.uid() is null or not exists (
    select 1 from public.quizzes z where z.id = p_quiz_id and z.owner_id = auth.uid()
  ) then
    raise exception 'that is not your quiz' using errcode = 'insufficient_privilege';
  end if;

  insert into public.quizzes (title, default_seconds, owner_id)
  select z.title || ' (copy)', z.default_seconds, auth.uid() from public.quizzes z where z.id = p_quiz_id
  returning id into v_new;

  insert into public.questions (quiz_id, position, text, choices, correct_index, seconds, recall_seconds)
  select v_new, q.position, q.text, q.choices, q.correct_index, q.seconds, q.recall_seconds
  from public.questions q where q.quiz_id = p_quiz_id;

  return v_new;
end;
$$;

grant execute on function public.duplicate_quiz(uuid) to authenticated;
