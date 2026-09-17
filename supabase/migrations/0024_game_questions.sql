-- A game keeps the questions it actually asked.
--
-- Until now the live game read from `questions`, which the teacher can edit. That
-- was survivable while quizzes were seeded by migration. It is not survivable now:
-- fix a typo after the lesson and the report describes a question nobody was
-- asked; reorder or delete one and `answers.question_index` points at the wrong
-- question entirely, silently and forever.
--
-- So a game copies its questions when it opens, and reads only from that copy. The
-- report is then true by construction, and a teacher who fixes a typo mid-lesson
-- no longer changes the question under the students' feet.

create table public.game_questions (
  game_id uuid not null references public.games (id) on delete cascade,
  position int not null,
  kind text not null,
  text text not null,
  choices text[],
  correct_index int,
  accepted text[],
  -- Resolved at copy time, so nothing downstream has to know about quiz defaults.
  seconds int not null,
  recall_seconds int not null,
  blurt_enabled boolean not null,
  image_path text,
  primary key (game_id, position)
);

alter table public.game_questions enable row level security;
revoke all on public.game_questions from anon, authenticated;

-- Everything reaches this through a SECURITY DEFINER function, so there is no
-- policy: a client has no business reading it directly, least of all the column
-- holding the correct answer.

-- Games played before this migration get a copy of the quiz as it stands today.
-- That is the best available record, not a true one — if the quiz was edited in
-- between, the copy is of the edited version. Games from here on are exact.
insert into public.game_questions
  (game_id, position, kind, text, choices, correct_index, accepted,
   seconds, recall_seconds, blurt_enabled, image_path)
select g.id, q.position, q.kind, q.text, q.choices, q.correct_index, q.accepted,
       coalesce(q.seconds, z.default_seconds), q.recall_seconds, q.blurt_enabled, q.image_path
from public.games g
join public.questions q on q.quiz_id = g.quiz_id
join public.quizzes z on z.id = g.quiz_id
on conflict do nothing;

-- ------------------------------------------------------------ create game ---

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

  insert into public.game_questions
    (game_id, position, kind, text, choices, correct_index, accepted,
     seconds, recall_seconds, blurt_enabled, image_path)
  select v_game.id, q.position, q.kind, q.text, q.choices, q.correct_index, q.accepted,
         coalesce(q.seconds, z.default_seconds), q.recall_seconds, q.blurt_enabled, q.image_path
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = p_quiz_id;

  insert into public.game_secrets (game_id) values (v_game.id)
  returning game_secrets.host_token into v_host_token;

  return query select v_game.code, v_host_token;
end;
$$;

grant execute on function public.create_game(uuid) to anon, authenticated;

-- ------------------------------------------------- everything reads the copy --

create or replace function public.question_limit_ms(p_game public.games)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (case
    when p_game.phase = 'recall'
      then coalesce(p_game.recall_seconds_override, q.recall_seconds)
    else q.seconds
  end + p_game.extra_seconds) * 1000
  from public.game_questions q
  where q.game_id = p_game.id and q.position = p_game.question_index;
$$;

revoke execute on function public.question_limit_ms(public.games) from public, anon, authenticated;

create or replace function public.opening_phase(p_game public.games, p_index int)
returns text
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p_game.blurt_enabled and coalesce(q.blurt_enabled, false) then 'recall'
    else 'question_open'
  end
  from public.game_questions q
  where q.game_id = p_game.id and q.position = p_index;
$$;

revoke execute on function public.opening_phase(public.games, int) from public, anon, authenticated;

create or replace function public.advance_game(p_host_token uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_last int;
begin
  select g.* into v_game
  from public.games g
  join public.game_secrets s on s.game_id = g.id
  where s.host_token = p_host_token
  for update;

  if not found then
    raise exception 'not the host' using errcode = 'insufficient_privilege';
  end if;

  -- From the copy, so deleting a question from the quiz cannot truncate a game
  -- that is already running.
  select max(q.position) into v_last from public.game_questions q where q.game_id = v_game.id;

  if v_game.phase = 'lobby' then
    update public.games
    set phase = public.opening_phase(v_game, 0), question_index = 0,
        question_started_at = now(), answered_count = 0, blurted_by = null
    where id = v_game.id;

  elsif v_game.phase = 'recall' then
    update public.games set phase = 'question_open', question_started_at = now()
      where id = v_game.id;

  elsif v_game.phase = 'blurt_claimed' then
    perform public.judge_blurt(p_host_token, false);

  elsif v_game.phase = 'question_open' then
    update public.games set phase = 'locked' where id = v_game.id;

  elsif v_game.phase = 'locked' then
    update public.games set phase = 'results' where id = v_game.id;

  elsif v_game.phase = 'results' then
    if v_game.question_index >= v_last then
      update public.games set phase = 'final', question_started_at = null
        where id = v_game.id;
    else
      update public.games
      set phase = public.opening_phase(v_game, v_game.question_index + 1),
          question_index = v_game.question_index + 1,
          question_started_at = now(), answered_count = 0, blurted_by = null
      where id = v_game.id;
    end if;
  end if;
end;
$$;

create or replace function public.record_answer(p_player_token uuid, p_choice int, p_text text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v_game public.games;
  v_question public.game_questions;
  v_limit int;
  v_elapsed int;
  v_correct boolean := false;
  v_awarded int := 0;
  v_bonus int := 0;
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

  select * into v_question from public.game_questions
  where game_id = v_game.id and position = v_game.question_index;

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
    v_bonus := public.streak_points(v_game, v_player.id);
  end if;

  insert into public.answers
    (game_id, player_id, question_index, choice, answer_text, ms_elapsed, awarded, bonus, correct)
  values (
    v_game.id, v_player.id, v_game.question_index,
    case when v_question.kind = 'text' then null else p_choice end,
    case when v_question.kind = 'text' then left(trim(p_text), 80) else null end,
    v_elapsed, v_awarded, v_bonus, v_correct
  );

  update public.players set score = score + v_awarded + v_bonus where id = v_player.id;
  update public.games set answered_count = answered_count + 1 where id = v_game.id;

  perform public.close_question_if_all_in(v_game.id);
exception
  when unique_violation then
    return;
end;
$$;

revoke execute on function public.record_answer(uuid, int, text) from public, anon, authenticated;

create or replace function public.blurt(p_player_token uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_player public.players;
  v_claimed int;
begin
  select p.* into v_player
  from public.players p
  join public.player_secrets s on s.player_id = p.id
  where s.token = p_player_token;

  if not found then
    raise exception 'not in this game' using errcode = 'no_data_found';
  end if;

  update public.games g
  set phase = 'blurt_claimed', blurted_by = v_player.id
  where g.id = v_player.game_id
    and g.phase = 'recall'
    and g.blurt_enabled
    and g.paused_at is null
    and g.blurted_by is null
    and exists (
      select 1 from public.game_questions q
      where q.game_id = g.id and q.position = g.question_index and q.blurt_enabled
    );

  get diagnostics v_claimed = row_count;
  return v_claimed = 1;
end;
$$;

grant execute on function public.blurt(uuid) to anon, authenticated;

-- ------------------------------------------------------------------ reads ---

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
            else q.seconds
          end) + v_game.extra_seconds)::int,
         (case when v_game.phase = 'results' then q.correct_index else null end)::int,
         (case when v_game.phase = 'results'
               then coalesce(q.accepted[1], q.choices[q.correct_index + 1]) end),
         q.image_path
  from public.game_questions q
  where q.game_id = v_game.id and q.position = v_game.question_index;
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
  q_image text,
  q_blurt boolean
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
         (q.seconds + case when v_game.phase = 'recall' then 0 else v_game.extra_seconds end)::int,
         (coalesce(v_game.recall_seconds_override, q.recall_seconds)
           + case when v_game.phase = 'recall' then v_game.extra_seconds else 0 end)::int,
         q.correct_index,
         q.accepted,
         q.image_path,
         q.blurt_enabled and v_game.blurt_enabled
  from public.game_questions q
  where q.game_id = v_game.id and q.position = v_game.question_index;
end;
$$;

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
         (select q.kind from public.game_questions q
           where q.game_id = v_game.id and q.position = v_game.question_index),
         (select coalesce(array_length(q.choices, 1), 0) from public.game_questions q
           where q.game_id = v_game.id and q.position = v_game.question_index);
end;
$$;

create or replace function public.distribution(p_code text)
returns table (answer_choice int, answer_count bigint)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_game public.games;
  v_question public.game_questions;
begin
  select * into v_game from public.games g where g.code = upper(trim(p_code));
  if not found or v_game.phase <> 'results' then
    return;
  end if;

  select * into v_question from public.game_questions q
  where q.game_id = v_game.id and q.position = v_game.question_index;

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

grant execute on function public.current_question(text) to anon, authenticated;
grant execute on function public.host_question(uuid) to anon, authenticated;
grant execute on function public.my_seat(uuid) to anon, authenticated;
grant execute on function public.distribution(text) to anon, authenticated;
