-- End the question the moment the room is done with it.
--
-- Sitting on a timer everyone has already beaten is dead air, and dead air in a
-- classroom is where the noise starts. This lives in the database rather than in
-- the host's browser for two reasons: it should be instant for every phone at
-- once, and it should not depend on the teacher's tab having noticed.
--
-- Counting is already right without special cases. A wrong blurt writes an
-- answers row and bumps answered_count, so a player locked out of the multiple
-- choice still counts as accounted for — otherwise the room would wait on
-- someone who is not allowed to reply.

create or replace function public.close_question_if_all_in(p_game_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_players int;
begin
  select * into v_game from public.games where id = p_game_id;
  if v_game.phase <> 'question_open' then
    return;
  end if;

  select count(*) into v_players from public.players where game_id = p_game_id;

  -- An empty room would otherwise satisfy "everyone has answered" immediately and
  -- skip the question before anyone could join.
  if v_players = 0 or v_game.answered_count < v_players then
    return;
  end if;

  update public.games set phase = 'locked'
  where id = p_game_id and phase = 'question_open';
end;
$$;

create or replace function public.submit_answer(p_player_token uuid, p_choice int)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v_game public.games;
  v_question public.questions;
  v_limit int;
  v_elapsed int;
  v_correct boolean := false;
  v_awarded int := 0;
  v_grace_ms constant int := 750;
begin
  select p.* into v_player
  from public.players p
  join public.player_secrets s on s.player_id = p.id
  where s.token = p_player_token;

  if not found then
    raise exception 'not in this game' using errcode = 'no_data_found';
  end if;

  select * into v_game from public.games where id = v_player.game_id for update;

  if v_game.phase <> 'question_open' then
    raise exception 'not taking answers' using errcode = 'check_violation';
  end if;

  select * into v_question from public.questions
  where quiz_id = v_game.quiz_id and position = v_game.question_index;

  v_limit := public.question_limit_ms(v_game);
  v_elapsed := (extract(epoch from (now() - v_game.question_started_at)) * 1000)::int;

  if v_elapsed > v_limit + v_grace_ms then
    raise exception 'too late' using errcode = 'check_violation';
  end if;

  v_elapsed := greatest(0, least(v_elapsed, v_limit));
  v_correct := p_choice = v_question.correct_index;

  if v_correct then
    v_awarded := round(1000.0 * (v_limit - v_elapsed) / v_limit);
  end if;

  insert into public.answers
    (game_id, player_id, question_index, choice, ms_elapsed, awarded, correct)
  values (v_game.id, v_player.id, v_game.question_index, p_choice, v_elapsed, v_awarded, v_correct);

  update public.players set score = score + v_awarded where id = v_player.id;
  update public.games set answered_count = answered_count + 1 where id = v_game.id;

  perform public.close_question_if_all_in(v_game.id);
exception
  when unique_violation then
    return;
end;
$$;

create or replace function public.judge_blurt(p_host_token uuid, p_correct boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_award constant int := 1500;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token
  for update;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  if v_game.phase <> 'blurt_claimed' or v_game.blurted_by is null then
    raise exception 'nobody is blurting' using errcode = 'check_violation';
  end if;

  insert into public.answers
    (game_id, player_id, question_index, choice, blurted, ms_elapsed, awarded, correct)
  values (v_game.id, v_game.blurted_by, v_game.question_index, null, true, 0,
          case when p_correct then v_award else 0 end, p_correct)
  on conflict do nothing;

  if p_correct then
    update public.players set score = score + v_award where id = v_game.blurted_by;
    update public.games set phase = 'results', answered_count = answered_count + 1
      where id = v_game.id;
  else
    update public.games
    set phase = 'question_open', question_started_at = now(), answered_count = answered_count + 1
      where id = v_game.id;
    -- In a room of one, the blurter was the whole room: do not put choices up
    -- for nobody.
    perform public.close_question_if_all_in(v_game.id);
  end if;
end;
$$;
