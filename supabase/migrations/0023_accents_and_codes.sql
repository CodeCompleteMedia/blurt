-- Two things found by watching a real room.

-- 1. A typed answer of "patino" was marked wrong against "Patiño".
--
-- The matcher forgave punctuation by turning everything outside a-z into a space,
-- which quietly turned ñ into a space too — so the accented and unaccented
-- spellings could never meet. Nobody hunts for ñ on a phone keyboard under a
-- countdown. Accents are now folded on both sides before anything is stripped.
--
-- A fixed translate() rather than the unaccent extension: it stays immutable, it
-- has no dependency to install, and it behaves the same in the throwaway database
-- the migrations are checked against.
create or replace function public.answer_key(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    trim(regexp_replace(
      regexp_replace(
        translate(
          lower(coalesce(p_text, '')),
          'áàâäãåāçčćďéèêëēěíìîïīľłñńňóòôöõøōřśšťúùûüūůýÿžźż',
          'aaaaaaacccdeeeeeeiiiiillnnnooooooorsstuuuuuuyyzzz'),
        '[^a-z0-9 ]', ' ', 'g'),
      '\s+', ' ', 'g')),
    '^(the|a|an) ', '')
$$;

revoke execute on function public.answer_key(text) from public, anon, authenticated;

-- 2. A room code of QPDLQ was read as QPDLO — by me, off a screenshot, which is
-- about what the back row of a classroom gets.
--
-- Codes already leave out O, 0, I and 1 so they cannot be mistyped. In the display
-- face a Q is an O with a tail nobody sees from twenty feet, and a student who
-- types the O gets "no such room". Q joins the list. Existing rooms keep theirs.
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

  loop
    v_code := (
      select string_agg(substr(v_alphabet, floor(random() * length(v_alphabet))::int + 1, 1), '')
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
