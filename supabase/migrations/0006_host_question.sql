-- A teacher judging a spoken answer needs to know what the answer is.
--
-- `current_question` deliberately withholds the choices during recall and the
-- correct index until results, which is right for every screen a student can
-- see — and useless for the person refereeing. This is the same question, read
-- through the host token: never withheld, never reachable without it.

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
         q.recall_seconds,
         q.correct_index
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

grant execute on function public.host_question(uuid) to anon, authenticated;
