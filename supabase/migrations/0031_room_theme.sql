-- The teacher's light or dark, carried by the room.
--
-- Until now the choice lived in the teacher's own browser, which is the one
-- screen in the room nobody else looks at. The wall and every phone are other
-- devices, so the only thing they share with the host is the room — and the
-- room is where the choice has to live for them to follow it.
--
-- Not a secret and not a score: it rides on `games`, which the broadcast
-- trigger already announces, so flipping it re-reads every screen the same way
-- any other change does.

alter table public.games
  add column theme text not null default 'dark'
  constraint games_theme_check check (theme in ('dark', 'light'));

-- The return type gains a column, and `create or replace` cannot change a
-- function's return type. Drop it first; nothing in the schema calls it.
drop function public.game_state(text);

create function public.game_state(p_code text)
returns table (
  id uuid,
  code text,
  quiz_id uuid,
  phase text,
  question_index int,
  question_started_at timestamptz,
  answered_count int,
  allow_late_join boolean,
  created_at timestamptz,
  blurted_by uuid,
  closed_at timestamptz,
  blurt_enabled boolean,
  reveal_immediately boolean,
  auto_next_seconds int,
  recall_seconds_override int,
  blurt_lockout boolean,
  blurt_penalty int,
  paused_at timestamptz,
  extra_seconds int,
  streak_bonus boolean,
  theme text
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select g.id, g.code, g.quiz_id, g.phase, g.question_index, g.question_started_at,
         g.answered_count, g.allow_late_join, g.created_at, g.blurted_by, g.closed_at,
         g.blurt_enabled, g.reveal_immediately, g.auto_next_seconds,
         g.recall_seconds_override, g.blurt_lockout, g.blurt_penalty, g.paused_at,
         g.extra_seconds, g.streak_bonus, g.theme
  from public.games g
  where g.code = upper(trim(p_code));
$$;

revoke execute on function public.game_state(text) from public;
grant execute on function public.game_state(text) to anon, authenticated;

-- Host authority is the host token, as with every other setting. Its own
-- function rather than a tenth argument on update_game_settings: that one has
-- changed signature once already, and the theme changes from a menu, not from
-- the settings panel.
create function public.set_game_theme(p_host_token uuid, p_theme text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game_id uuid;
begin
  if p_theme is null or p_theme not in ('dark', 'light') then
    raise exception 'theme must be dark or light' using errcode = 'invalid_parameter_value';
  end if;

  select g.id into v_game_id
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token;

  if v_game_id is null then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  -- Only when it changes, so re-sending the same choice does not wake every
  -- screen in the room for nothing.
  update public.games set theme = p_theme where id = v_game_id and theme is distinct from p_theme;
end;
$$;

revoke execute on function public.set_game_theme(uuid, text) from public;
grant execute on function public.set_game_theme(uuid, text) to anon, authenticated;
