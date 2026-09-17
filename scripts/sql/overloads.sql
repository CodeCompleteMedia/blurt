-- No function in this schema may have two signatures.
--
-- `create or replace function` does not replace when the argument list changes
-- — it adds an overload, silently. Every settings change in this project broke
-- once because of that: calls naming a subset of arguments became ambiguous,
-- and the app looked healthy right up until a teacher touched a toggle.
--
-- Changing a signature therefore means `drop function` with the OLD argument
-- list first. This is the check that says whether every migration remembered.
\set ON_ERROR_STOP on
\pset pager off

do $$
declare
  dupes text;
  n int;
begin
  select count(*), string_agg(
           format('%s takes %s', proname, sigs), e'\n       ')
    into n, dupes
  from (
    select p.proname,
           string_agg(pg_get_function_identity_arguments(p.oid), '  /  ' order by p.oid) as sigs
    from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public'
    group by p.proname
    having count(*) > 1
  ) d;

  if n > 0 then
    raise exception '% function name(s) have more than one signature — a migration replaced a function without dropping the old argument list first:%s       %',
      n, e'\n', dupes;
  end if;

  raise notice 'ok  every public function has exactly one signature';
end $$;

-- And every function meant to be called from the browser needs its grant said
-- out loud, because the schema's default privileges are closed. A function with
-- no grant is internal; the thing to catch is the reverse of the 2026-09-16 bug,
-- where internal helpers were reachable with the anon key.
do $$
declare r record; reachable text := '';
begin
  for r in
    select p.proname, pg_get_function_identity_arguments(p.oid) as args
    from pg_proc p
    join pg_namespace ns on ns.oid = p.pronamespace
    where ns.nspname = 'public'
      and p.proname in ('answer_key', 'record_answer', 'opening_phase', 'name_is_clean')
      and (has_function_privilege('anon', p.oid, 'execute')
        or has_function_privilege('authenticated', p.oid, 'execute'))
  loop
    reachable := reachable || format(e'\n       %s(%s)', r.proname, r.args);
  end loop;

  if reachable <> '' then
    raise exception 'internal helpers are callable from the browser:%', reachable;
  end if;

  raise notice 'ok  internal helpers are not callable by anon or authenticated';
end $$;
