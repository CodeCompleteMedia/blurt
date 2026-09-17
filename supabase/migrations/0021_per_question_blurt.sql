-- Blurting, per question.
--
-- It was one switch for a whole game, which is the wrong grain. Recall is worth
-- more than recognition — that is the point of the window — but only where the
-- two differ. On a typed question they do not: the student has to produce the
-- answer from memory either way, so the window adds nothing but a race, and a
-- pause showing the question with no way to answer it yet.
--
-- The game-level setting stays as a master switch ("no blurting with this class
-- today"); the two compose, so a question opens in recall only if both allow it.

alter table public.questions add column blurt_enabled boolean not null default true;

-- Existing typed questions were all in recall until now. Nobody has to go and
-- find them.
update public.questions set blurt_enabled = false where kind = 'text';

-- Deliberately not a constraint forbidding it on typed questions. Defaulting it
-- off is the editor's job — a column default cannot read another column — and a
-- teacher who later wants to try buzz-in-then-type should not have to migrate the
-- schema to find out it feels wrong.

-- Which phase a question opens in, in one place rather than in each branch of
-- advance_game that reaches for it.
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
  from public.questions q
  where q.quiz_id = p_game.quiz_id and q.position = p_index;
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

  select max(q.position) into v_last from public.questions q where q.quiz_id = v_game.quiz_id;

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

-- The floor can only be claimed in `recall`, and a question that forbids blurting
-- never enters it — but the rule belongs where it cannot be reached around, not
-- inferred from the phase machine two functions away.
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
      select 1 from public.questions q
      where q.quiz_id = g.quiz_id and q.position = g.question_index and q.blurt_enabled
    );

  get diagnostics v_claimed = row_count;
  return v_claimed = 1;
end;
$$;

-- The teacher's screen shows whether this question is a blurt question, so the
-- phase label is not the only clue.
drop function public.host_question(uuid);

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
         (coalesce(q.seconds, z.default_seconds)
           + case when v_game.phase = 'recall' then 0 else v_game.extra_seconds end)::int,
         (coalesce(v_game.recall_seconds_override, q.recall_seconds)
           + case when v_game.phase = 'recall' then v_game.extra_seconds else 0 end)::int,
         q.correct_index,
         q.accepted,
         q.image_path,
         q.blurt_enabled and v_game.blurt_enabled
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

grant execute on function public.host_question(uuid) to anon, authenticated;

-- ------------------------------------------------------- copying keeps up ---

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
    (quiz_id, position, kind, text, choices, correct_index, accepted,
     seconds, recall_seconds, blurt_enabled, image_path)
  select v_new, q.position, q.kind, q.text, q.choices, q.correct_index, q.accepted,
         q.seconds, q.recall_seconds, q.blurt_enabled, q.image_path
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
    (quiz_id, position, kind, text, choices, correct_index, accepted,
     seconds, recall_seconds, blurt_enabled, image_path)
  select v_new, q.position, q.kind, q.text, q.choices, q.correct_index, q.accepted,
         q.seconds, q.recall_seconds, q.blurt_enabled, q.image_path
  from public.questions q where q.quiz_id = p_quiz_id;

  return v_new;
end;
$$;

grant execute on function public.copy_sample_quiz() to authenticated;
grant execute on function public.duplicate_quiz(uuid) to authenticated;
