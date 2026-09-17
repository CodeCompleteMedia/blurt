-- Just enough of Supabase for the migrations to run against a bare Postgres.
-- Used only by scripts/check-migrations.sh; never applied to a real project.

create role anon nologin;
create role authenticated nologin;
create publication supabase_realtime;

-- auth: who is calling. Supabase reads the JWT it verified into this setting, so
-- a test can impersonate a teacher with:
--   select set_config('request.jwt.claims', '{"sub":"<uuid>"}', false);
create schema auth;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claims', true)::jsonb ->> 'sub', '')::uuid
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
