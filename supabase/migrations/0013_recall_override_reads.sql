-- The recall override has to reach the screens too.
--
-- 0012 taught `question_limit_ms` about the game-wide recall window, which is
-- what the server enforces — but `current_question` still returned the value
-- baked into the question, so every countdown on every screen would have run a
-- different length from the deadline actually being applied. A timer that
-- disagrees with the rule is worse than no timer.

create or replace function public.current_question(p_code text)
returns table (q_position int, q_text text, q_choices text[], q_seconds int, q_correct_index int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select * into v_game from public.games g where g.code = upper(trim(p_code));
  if not found or v_game.question_index < 0 then
    return;
  end if;

  return query
  select q.position,
         q.text,
         (case when v_game.phase in ('recall', 'blurt_claimed') then null else q.choices end),
         (case
            when v_game.phase = 'recall'
              then coalesce(v_game.recall_seconds_override, q.recall_seconds)
            else coalesce(q.seconds, z.default_seconds)
          end)::int,
         (case when v_game.phase = 'results' then q.correct_index else null end)::int
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

create or replace function public.host_question(p_host_token uuid)
returns table (
  q_position int,
  q_text text,
  q_choices text[],
  q_seconds int,
  q_recall_seconds int,
  q_correct_index int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  if v_game.question_index < 0 then
    return;
  end if;

  return query
  select q.position,
         q.text,
         q.choices,
         coalesce(q.seconds, z.default_seconds)::int,
         coalesce(v_game.recall_seconds_override, q.recall_seconds)::int,
         q.correct_index
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;
