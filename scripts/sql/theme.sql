-- The room's light or dark is the host's to set, and only for their own room.
--
-- It is readable by anyone holding the room code, like the rest of
-- `game_state`, because the wall and the phones are not signed in. Setting it
-- needs the host token. Two rooms, two teachers, so a missing game filter would
-- show up as the other room changing too.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select public.copy_sample_quiz() as qa \gset
select code as ca, host_token as ha from public.create_game(:'qa') \gset
select set_config('blurt.ha', :'ha', false) \gset x
select set_config('blurt.ca', :'ca', false) \gset x

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false) \gset x
select public.copy_sample_quiz() as qb \gset
select code as cb, host_token as hb from public.create_game(:'qb') \gset
select set_config('blurt.hb', :'hb', false) \gset x
select set_config('blurt.cb', :'cb', false) \gset x

do $$
declare
  ha uuid := current_setting('blurt.ha')::uuid;
  hb uuid := current_setting('blurt.hb')::uuid;
  ca text := current_setting('blurt.ca');
  cb text := current_setting('blurt.cb');
  t text; refused boolean;
begin
  -- A new room is dark, and a screen holding only the code can read that.
  set local role anon;
  select g.theme into t from public.game_state(ca) g;
  reset role;
  if t is distinct from 'dark' then raise exception 'a new room should be dark, got %', t; end if;

  -- The host turns the lights up — on their room and nobody else's.
  perform public.set_game_theme(ha, 'light');
  select g.theme into t from public.game_state(ca) g;
  if t is distinct from 'light' then raise exception 'the host set light, room reads %', t; end if;
  select g.theme into t from public.game_state(cb) g;
  if t is distinct from 'dark' then raise exception 'the other room changed too: %', t; end if;

  -- A token that is not a host token changes nothing.
  refused := false;
  begin
    perform public.set_game_theme('00000000-0000-0000-0000-000000000000', 'dark');
  exception when insufficient_privilege then refused := true;
  end;
  if not refused then raise exception 'a made-up token was allowed to set the theme'; end if;

  -- Nor can anything but the two values get in.
  refused := false;
  begin
    perform public.set_game_theme(ha, 'neon');
  exception when invalid_parameter_value then refused := true;
  end;
  if not refused then raise exception 'a theme that is neither dark nor light was accepted'; end if;
  select g.theme into t from public.game_state(ca) g;
  if t is distinct from 'light' then raise exception 'a refused value still changed the room: %', t; end if;

  perform public.set_game_theme(hb, 'light');
  perform public.set_game_theme(hb, 'dark');
  select g.theme into t from public.game_state(cb) g;
  if t is distinct from 'dark' then raise exception 'back to dark did not stick: %', t; end if;

  raise notice 'ok  a room carries its host''s theme, and only its host can set it';
end $$;
