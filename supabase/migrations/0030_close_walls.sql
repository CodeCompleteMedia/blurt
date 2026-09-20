-- Two doors 0029 left on the latch.
--
-- Found by asking the live REST API what the anon key could reach, rather than
-- by asking the throwaway database — which could not have told the truth here,
-- because it did not model Supabase's default grants. It does now.

-- 1. `walls` was the only table in the schema still carrying a SELECT grant.
--    Row level security was holding it shut (the table has no policies, so it
--    denies everyone), but every other table in this schema is closed at the
--    grant as well, and a table one `create policy` away from being public is
--    not the same as a table nobody can address. `wall_room` is how a display
--    reads its own row, and that has not changed.
revoke all on public.walls from anon, authenticated;

-- 2. Every function still carried Postgres's built-in EXECUTE-to-PUBLIC, which
--    is what 0016 believed it had turned off and had not. Nothing leaked —
--    each one gates itself on auth.uid() or a token — but it meant a function
--    that ever forgot its own gate would be reachable by anyone holding the
--    public key, which is every student in the room.
--
--    This removes only the PUBLIC grant. The explicit `grant execute ... to
--    anon, authenticated` lines that make up the actual API are separate
--    grants and survive untouched, so nothing the client calls changes.
revoke execute on all functions in schema public from public;
