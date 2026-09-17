-- Three kinds of question: pick one of up to four, true or false, or type it.
--
-- Typed answers are the expensive one, and the cost is all in judging them. The
-- database forgives what a marker would forgive — case, stray spaces, punctuation,
-- a leading "the" — and nothing else. Spelling is not forgiven: a fuzzy match that
-- accepts "mitocondria" will also accept answers that are simply wrong, and a
-- student who loses a point to a typo can argue it with a teacher, while one who
-- gains a point from a lucky near-miss never will.

-- ----------------------------------------------------------------- schema ---

alter table public.questions
  add column kind text not null default 'choice' check (kind in ('choice', 'truefalse', 'text')),
  add column accepted text[],
  -- Arrives with the image slice; here now so the read functions change shape once.
  add column image_path text;

alter table public.questions drop constraint questions_choices_check;
alter table public.questions drop constraint questions_correct_index_check;
alter table public.questions alter column choices drop not null;
alter table public.questions alter column correct_index drop not null;

-- Every branch is wrapped in coalesce(..., false) on purpose. A CHECK only rejects
-- a row when the expression is *false*; NULL passes. array_length of an empty
-- array is NULL, so "array_length(accepted, 1) >= 1" waved through a typed
-- question with no accepted answers at all — unanswerable, and silently so.
alter table public.questions add constraint questions_shape check (
  coalesce(
    case kind
      when 'choice' then
        array_length(choices, 1) between 2 and 4
        and correct_index between 0 and array_length(choices, 1) - 1
        and accepted is null
      when 'truefalse' then
        choices = array['True', 'False'] and correct_index in (0, 1) and accepted is null
      when 'text' then
        choices is null and correct_index is null and array_length(accepted, 1) >= 1
    end,
    false)
);

alter table public.answers add column answer_text text check (char_length(answer_text) <= 80);

alter table public.answers drop constraint answers_shape;
alter table public.answers add constraint answers_shape check (
  (blurted and choice is null and answer_text is null)
  or (not blurted and (choice is not null) <> (answer_text is not null))
);

-- --------------------------------------------------------------- matching ---

-- What two answers have to share to count as the same answer. Also what makes
-- "<ol>" and "ol" equal, which is the forgiving reading for a class that is
-- typing HTML on a phone keyboard.
create or replace function public.answer_key(p_text text)
returns text
language sql
immutable
as $$
  select regexp_replace(
    trim(regexp_replace(
      regexp_replace(lower(coalesce(p_text, '')), '[^a-z0-9 ]', ' ', 'g'),
      '\s+', ' ', 'g')),
    '^(the|a|an) ', '')
$$;

revoke execute on function public.answer_key(text) from public, anon, authenticated;

-- ---------------------------------------------------------------- answers ---

-- One body for both ways of answering, so the rules about timing, pausing,
-- lockout and scoring cannot drift apart between them.
create or replace function public.record_answer(p_player_token uuid, p_choice int, p_text text)
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

  if v_game.paused_at is not null then
    raise exception 'paused' using errcode = 'check_violation';
  end if;

  if v_game.blurt_lockout and exists (
    select 1 from public.answers a
    where a.game_id = v_game.id and a.player_id = v_player.id
      and a.question_index = v_game.question_index and a.blurted and not a.correct
  ) then
    return;
  end if;

  select * into v_question from public.questions
  where quiz_id = v_game.quiz_id and position = v_game.question_index;

  -- The right kind of answer for the kind of question. A phone built from this
  -- repo never gets this wrong; a student at the console might try.
  if v_question.kind = 'text' then
    if p_text is null or char_length(trim(p_text)) = 0 then
      raise exception 'type an answer' using errcode = 'check_violation';
    end if;
    v_correct := public.answer_key(p_text) in (
      select public.answer_key(a) from unnest(v_question.accepted) as a
    );
  else
    if p_choice is null or p_choice not between 0 and array_length(v_question.choices, 1) - 1 then
      raise exception 'not one of the choices' using errcode = 'check_violation';
    end if;
    v_correct := p_choice = v_question.correct_index;
  end if;

  v_limit := public.question_limit_ms(v_game);
  v_elapsed := (extract(epoch from (now() - v_game.question_started_at)) * 1000)::int;

  if v_elapsed > v_limit + v_grace_ms then
    raise exception 'too late' using errcode = 'check_violation';
  end if;

  v_elapsed := greatest(0, least(v_elapsed, v_limit));
  if v_correct then
    v_awarded := round(1000.0 * (v_limit - v_elapsed) / v_limit);
  end if;

  insert into public.answers
    (game_id, player_id, question_index, choice, answer_text, ms_elapsed, awarded, correct)
  values (
    v_game.id, v_player.id, v_game.question_index,
    case when v_question.kind = 'text' then null else p_choice end,
    case when v_question.kind = 'text' then left(trim(p_text), 80) else null end,
    v_elapsed, v_awarded, v_correct
  );

  update public.players set score = score + v_awarded where id = v_player.id;
  update public.games set answered_count = answered_count + 1 where id = v_game.id;

  perform public.close_question_if_all_in(v_game.id);
exception
  when unique_violation then
    return;
end;
$$;

revoke execute on function public.record_answer(uuid, int, text) from public, anon, authenticated;

create or replace function public.submit_answer(p_player_token uuid, p_choice int)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.record_answer(p_player_token, p_choice, null);
$$;

create or replace function public.submit_text_answer(p_player_token uuid, p_text text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.record_answer(p_player_token, null, p_text);
$$;

-- ------------------------------------------------------------------ reads ---

-- Signatures change, and `create or replace` would add overloads beside the old
-- ones rather than replacing them. Drop first.
drop function public.current_question(text);
drop function public.host_question(uuid);
drop function public.my_seat(uuid);

create function public.current_question(p_code text)
returns table (
  q_position int,
  q_kind text,
  q_text text,
  q_choices text[],
  q_seconds int,
  q_correct_index int,
  q_answer text,
  q_image text
)
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
         q.kind,
         q.text,
         (case when v_game.phase in ('recall', 'blurt_claimed') then null else q.choices end),
         ((case
            when v_game.phase = 'recall'
              then coalesce(v_game.recall_seconds_override, q.recall_seconds)
            else coalesce(q.seconds, z.default_seconds)
          end) + v_game.extra_seconds)::int,
         (case when v_game.phase = 'results' then q.correct_index else null end)::int,
         -- The answer in words, whatever kind of question it was — so the wall has
         -- one thing to print under "The answer was".
         (case when v_game.phase = 'results'
               then coalesce(q.accepted[1], q.choices[q.correct_index + 1]) end),
         q.image_path
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

create function public.host_question(p_host_token uuid)
returns table (
  q_position int,
  q_kind text,
  q_text text,
  q_choices text[],
  q_seconds int,
  q_recall_seconds int,
  q_correct_index int,
  q_accepted text[],
  q_image text
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
         q.kind,
         q.text,
         q.choices,
         (coalesce(q.seconds, z.default_seconds)
           + case when v_game.phase = 'recall' then 0 else v_game.extra_seconds end)::int,
         (coalesce(v_game.recall_seconds_override, q.recall_seconds)
           + case when v_game.phase = 'recall' then v_game.extra_seconds else 0 end)::int,
         q.correct_index,
         q.accepted,
         q.image_path
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

-- The phone never reads the question, so its seat tells it what to draw: how many
-- shapes, or a text box. That is all it learns.
create function public.my_seat(p_player_token uuid)
returns table (
  player_id uuid,
  player_name text,
  answered_current boolean,
  locked_out boolean,
  question_kind text,
  choice_count int
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v_game public.games;
begin
  select p.* into v_player
  from public.players p
  join public.player_secrets s on s.player_id = p.id
  where s.token = p_player_token;

  if not found then
    raise exception 'not in this game' using errcode = 'no_data_found';
  end if;

  select * into v_game from public.games where id = v_player.game_id;

  return query
  select v_player.id,
         v_player.name,
         exists (
           select 1 from public.answers a
           where a.game_id = v_game.id and a.player_id = v_player.id
             and a.question_index = v_game.question_index and not a.blurted
         ),
         v_game.blurt_lockout and exists (
           select 1 from public.answers a
           where a.game_id = v_game.id and a.player_id = v_player.id
             and a.question_index = v_game.question_index and a.blurted and not a.correct
         ),
         (select q.kind from public.questions q
           where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index),
         (select coalesce(array_length(q.choices, 1), 0) from public.questions q
           where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index);
end;
$$;

-- As many columns as the question has choices, rather than always four.
create or replace function public.distribution(p_code text)
returns table (answer_choice int, answer_count bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_question public.questions;
begin
  select * into v_game from public.games g where g.code = upper(trim(p_code));
  if not found or v_game.phase <> 'results' then
    return;
  end if;

  select * into v_question from public.questions q
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;

  if v_question.kind = 'text' then
    return;
  end if;

  return query
  select c.choice, count(a.id)
  from generate_series(0, array_length(v_question.choices, 1) - 1) as c(choice)
  left join public.answers a
    on a.game_id = v_game.id
   and a.question_index = v_game.question_index
   and (a.choice = c.choice or (a.blurted and a.correct and c.choice = v_question.correct_index))
  group by c.choice
  order by c.choice;
end;
$$;

-- What the room typed, most common first. This puts students' own words on the
-- projector, so it goes through the same filter as their names: a class will
-- find out within one question that the answer box is a way onto the wall.
create or replace function public.text_distribution(p_code text)
returns table (answer_text text, answer_count bigint, is_correct boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
begin
  select * into v_game from public.games g where g.code = upper(trim(p_code));
  if not found or v_game.phase <> 'results' then
    return;
  end if;

  return query
  select min(a.answer_text), count(*), bool_or(a.correct)
  from public.answers a
  where a.game_id = v_game.id
    and a.question_index = v_game.question_index
    and a.answer_text is not null
    and public.name_is_clean(a.answer_text)
  group by public.answer_key(a.answer_text)
  order by count(*) desc, min(a.answer_text)
  limit 6;
end;
$$;

-- ---------------------------------------------------- copying keeps up ---

create or replace function public.copy_sample_quiz()
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_template constant uuid := '11111111-1111-1111-1111-111111111111';
  v_new uuid;
begin
  if auth.uid() is null then
    raise exception 'sign in first' using errcode = 'insufficient_privilege';
  end if;

  insert into public.quizzes (title, default_seconds, owner_id)
  select z.title, z.default_seconds, auth.uid() from public.quizzes z where z.id = v_template
  returning id into v_new;

  insert into public.questions
    (quiz_id, position, kind, text, choices, correct_index, accepted, seconds, recall_seconds, image_path)
  select v_new, q.position, q.kind, q.text, q.choices, q.correct_index, q.accepted,
         q.seconds, q.recall_seconds, q.image_path
  from public.questions q where q.quiz_id = v_template;

  return v_new;
end;
$$;

create or replace function public.duplicate_quiz(p_quiz_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_new uuid;
begin
  if auth.uid() is null or not exists (
    select 1 from public.quizzes z where z.id = p_quiz_id and z.owner_id = auth.uid()
  ) then
    raise exception 'that is not your quiz' using errcode = 'insufficient_privilege';
  end if;

  insert into public.quizzes (title, default_seconds, owner_id)
  select z.title || ' (copy)', z.default_seconds, auth.uid() from public.quizzes z where z.id = p_quiz_id
  returning id into v_new;

  insert into public.questions
    (quiz_id, position, kind, text, choices, correct_index, accepted, seconds, recall_seconds, image_path)
  select v_new, q.position, q.kind, q.text, q.choices, q.correct_index, q.accepted,
         q.seconds, q.recall_seconds, q.image_path
  from public.questions q where q.quiz_id = p_quiz_id;

  return v_new;
end;
$$;

-- ------------------------------------------------------------------ grants --

grant execute on function public.submit_answer(uuid, int) to anon, authenticated;
grant execute on function public.submit_text_answer(uuid, text) to anon, authenticated;
grant execute on function public.current_question(text) to anon, authenticated;
grant execute on function public.host_question(uuid) to anon, authenticated;
grant execute on function public.my_seat(uuid) to anon, authenticated;
grant execute on function public.distribution(text) to anon, authenticated;
grant execute on function public.text_distribution(text) to anon, authenticated;
grant execute on function public.copy_sample_quiz() to authenticated;
grant execute on function public.duplicate_quiz(uuid) to authenticated;
