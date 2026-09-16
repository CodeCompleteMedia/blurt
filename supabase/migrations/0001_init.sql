-- blurt: schema, policies and the functions that own every rule.
--
-- The threat model is a student with the element inspector and the anon key,
-- which is public by design. So the anon role can read only what is safe to
-- project on a wall, and can write nothing at all: every mutation goes through
-- a SECURITY DEFINER function below, where the server clock and the correct
-- answer live. Anything a client sends that it could lie about — elapsed time,
-- score, identity — is ignored and recomputed here.

-- ---------------------------------------------------------------- content ---

create table public.quizzes (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  default_seconds int not null default 20 check (default_seconds between 5 and 120),
  created_at timestamptz not null default now()
);

create table public.questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes (id) on delete cascade,
  position int not null check (position >= 0),
  text text not null,
  choices text[] not null check (array_length(choices, 1) = 4),
  correct_index int not null check (correct_index between 0 and 3),
  seconds int check (seconds between 5 and 120),
  unique (quiz_id, position)
);

-- ------------------------------------------------------------------ games ---

-- Public-safe columns only. This table is readable by anyone with the anon key
-- and is what Realtime broadcasts, so nothing secret may ever live here.
create table public.games (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{4,8}$'),
  quiz_id uuid not null references public.quizzes (id),
  phase text not null default 'lobby'
    check (phase in ('lobby', 'question_open', 'locked', 'results', 'final')),
  question_index int not null default -1,
  question_started_at timestamptz,
  answered_count int not null default 0,
  allow_late_join boolean not null default true,
  created_at timestamptz not null default now()
);

-- The host token lives apart from the game precisely because `games` is public.
-- Without this split, a student reading the games row could end the lesson.
create table public.game_secrets (
  game_id uuid primary key references public.games (id) on delete cascade,
  host_token uuid not null default gen_random_uuid()
);

-- ---------------------------------------------------------------- players ---

create table public.players (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  name text not null check (char_length(trim(name)) between 2 and 20),
  score int not null default 0,
  joined_at timestamptz not null default now()
);

create unique index players_unique_name on public.players (game_id, lower(trim(name)));
create index players_by_game on public.players (game_id);

-- Same split, same reason: the roster is public, the seat token is not.
create table public.player_secrets (
  player_id uuid primary key references public.players (id) on delete cascade,
  token uuid not null default gen_random_uuid()
);

create unique index player_secrets_token on public.player_secrets (token);

-- ---------------------------------------------------------------- answers ---

create table public.answers (
  id uuid primary key default gen_random_uuid(),
  game_id uuid not null references public.games (id) on delete cascade,
  player_id uuid not null references public.players (id) on delete cascade,
  question_index int not null,
  choice int not null check (choice between 0 and 3),
  ms_elapsed int not null,
  awarded int not null,
  created_at timestamptz not null default now(),
  -- One answer per player per question, enforced by the database rather than by
  -- a disabled button.
  unique (game_id, player_id, question_index)
);

create index answers_by_question on public.answers (game_id, question_index);

-- ------------------------------------------------------- row level security --

alter table public.quizzes enable row level security;
alter table public.questions enable row level security;
alter table public.games enable row level security;
alter table public.game_secrets enable row level security;
alter table public.players enable row level security;
alter table public.player_secrets enable row level security;
alter table public.answers enable row level security;

-- No policy means no access. questions, game_secrets, player_secrets and answers
-- are deliberately left with none: correct answers, tokens and who-picked-what
-- reach clients only through the functions below, and only once the projector
-- has revealed them.

create policy games_readable on public.games
  for select to anon, authenticated using (true);

create policy players_readable on public.players
  for select to anon, authenticated using (true);

create policy quizzes_readable on public.quizzes
  for select to anon, authenticated using (true);

revoke all on all tables in schema public from anon, authenticated;
grant select on public.games, public.players, public.quizzes to anon, authenticated;

-- Realtime: phase changes and the roster push instead of being polled.
alter publication supabase_realtime add table public.games;
alter publication supabase_realtime add table public.players;
