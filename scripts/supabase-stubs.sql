-- Just enough of Supabase for the migrations to run against a bare Postgres.
-- Used only by scripts/check-migrations.sh; never applied to a real project.

create role anon nologin;
create role authenticated nologin;

-- Supabase hands every NEW table in `public` to anon and authenticated by
-- default. Without this line the throwaway database is safer than production,
-- which is the worst way for a test database to differ: a table added without
-- its `revoke all` passes locally and ships open. That is exactly what happened
-- to `walls` in 0029, caught only by poking the live REST API by hand.
--
-- Functions are not listed here because Postgres already grants EXECUTE to
-- PUBLIC on every new function by itself — see gotcha 1 in the notes, and
-- scripts/sql/overloads.sql.
alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated;
create publication supabase_realtime;

-- auth: who is calling. Supabase reads the JWT it verified into this setting, so
-- a test can impersonate a teacher with:
--   select set_config('request.jwt.claims', '{"sub":"<uuid>"}', false);
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
-- Signed out is null, not an error. The old one cast '' to jsonb and threw, which
-- made "nobody is signed in" indistinguishable from "the function is broken" and
-- quietly turned some checks into tests of the wrong failure.
create function auth.uid() returns uuid language plpgsql stable as $$
declare claims text := current_setting('request.jwt.claims', true);
begin
  if claims is null or btrim(claims) = '' then return null; end if;
  return nullif(claims::jsonb ->> 'sub', '')::uuid;
exception when others then
  return null;
end;
$$;
grant usage on schema auth to anon, authenticated;

-- storage: only the shape the policies refer to.
create schema storage;
create table storage.buckets (
  id text primary key, name text, public boolean default false,
  file_size_limit bigint, allowed_mime_types text[]
);
create table storage.objects (
  id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid
);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1 : array_length(string_to_array(name, '/'), 1) - 1]
$$;

-- realtime: enough to apply the broadcast migration and watch a trigger fire.
-- This is NOT Supabase's Realtime server — it proves the trigger runs, builds
-- the right topic and is refused to the wrong caller. Whether a browser
-- actually receives the message can only be tested against a real project.
create schema realtime;
create table realtime.messages (
  id bigserial primary key,
  topic text not null,
  extension text not null default 'broadcast',
  event text,
  payload jsonb,
  private boolean default false,
  inserted_at timestamptz not null default now()
);
alter table realtime.messages enable row level security;
create function realtime.topic() returns text language sql stable as $$
  select current_setting('realtime.topic', true)
$$;
create function realtime.send(payload jsonb, event text, topic text, private boolean default true)
returns void language sql as $$
  insert into realtime.messages (topic, event, payload, private)
  values (topic, event, payload, private);
$$;
grant usage on schema realtime to anon, authenticated;
