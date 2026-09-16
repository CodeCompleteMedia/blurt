-- The mechanic the thing is named after.
--
-- A question now opens with its choices hidden. For a few seconds anyone can
-- claim the floor; the claimant says the answer out loud and the teacher marks
-- it. Get it right and it is worth more than any multiple-choice answer. Get it
-- wrong and you are out of this question while the rest of the room gets the
-- choices.
--
-- The point is that recall is the high-value path and recognition is the
-- fallback — which means the choices must be withheld by the database, not just
-- by the screen. A student with the console would otherwise read them straight
-- out of `current_question`.

-- ----------------------------------------------------------------- schema ---

alter table public.games drop constraint games_phase_check;

alter table public.games add constraint games_phase_check check (
  phase in ('lobby', 'recall', 'blurt_claimed', 'question_open', 'locked', 'results', 'final')
);

-- Who holds the floor. Null unless someone has claimed it this question.
alter table public.games add column blurted_by uuid references public.players (id) on delete set null;

-- How long the room gets before the choices appear.
alter table public.questions add column recall_seconds int not null default 8
  check (recall_seconds between 3 and 60);

-- A blurt is an answer with no choice attached: it records what happened, and
-- the existing unique index on (game, player, question) is what then locks a
-- wrong blurter out of the multiple choice. No second enforcement path.
alter table public.answers alter column choice drop not null;
alter table public.answers add column blurted boolean not null default false;
alter table public.answers add constraint answers_shape check (
  (blurted and choice is null) or (not blurted and choice is not null)
);

-- --------------------------------------------------------------- helpers ---

-- Recall runs on its own clock; the multiple-choice timer restarts when the
-- choices appear.
create or replace function public.question_limit_ms(p_game public.games)
returns int
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p_game.phase = 'recall' then q.recall_seconds * 1000
    else coalesce(q.seconds, z.default_seconds) * 1000
  end
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = p_game.quiz_id
    and q.position = p_game.question_index;
$$;

-- ------------------------------------------------------------------ blurt ---

-- Claiming the floor is one conditional update. Whoever the database writes
-- first wins and everyone else's claim matches zero rows — there is no tie to
-- resolve and no client-supplied timestamp to forge. The network is still a
-- race, but the claim itself is exact.
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

  update public.games
  set phase = 'blurt_claimed', blurted_by = v_player.id
  where id = v_player.game_id
    and phase = 'recall'
    and blurted_by is null;

  get diagnostics v_claimed = row_count;
  return v_claimed = 1;
end;
$$;

-- The teacher's verdict. Right: worth more than any multiple-choice answer,
-- and the question is over. Wrong: the blurter is locked out by the answer row
-- this writes, and the choices go up for everyone else.
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

  insert into public.answers (game_id, player_id, question_index, choice, blurted, ms_elapsed, awarded)
  values (v_game.id, v_game.blurted_by, v_game.question_index, null, true, 0,
          case when p_correct then v_award else 0 end)
  on conflict do nothing;

  if p_correct then
    update public.players set score = score + v_award where id = v_game.blurted_by;
    update public.games
    set phase = 'results', answered_count = answered_count + 1
    where id = v_game.id;
  else
    -- The room gets the choices, and a fresh clock to answer them on.
    update public.games
    set phase = 'question_open', question_started_at = now(), answered_count = answered_count + 1
    where id = v_game.id;
  end if;
end;
$$;

-- ---------------------------------------------------------------- advance ---

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
    update public.games set phase = 'recall', question_index = 0,
      question_started_at = now(), answered_count = 0, blurted_by = null
      where id = v_game.id;

  elsif v_game.phase = 'recall' then
    -- Nobody claimed it. The choices go up and the timer restarts.
    update public.games set phase = 'question_open', question_started_at = now()
      where id = v_game.id;

  elsif v_game.phase = 'blurt_claimed' then
    -- Advancing past an unjudged blurt counts as wrong, so a teacher who hits
    -- the wrong key cannot strand the room.
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
      update public.games set phase = 'recall',
        question_index = v_game.question_index + 1,
        question_started_at = now(), answered_count = 0, blurted_by = null
        where id = v_game.id;
    end if;
  end if;
end;
$$;

-- ------------------------------------------------------------------ reads ---

-- Choices are now withheld during recall for the same reason the correct answer
-- is withheld before results: a condition the client cannot rewrite.
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
         (case when v_game.phase = 'recall' then q.recall_seconds
               else coalesce(q.seconds, z.default_seconds) end)::int,
         (case when v_game.phase = 'results' then q.correct_index else null end)::int
  from public.questions q
  join public.quizzes z on z.id = q.quiz_id
  where q.quiz_id = v_game.quiz_id and q.position = v_game.question_index;
end;
$$;

-- Who is holding the floor, for the wall and the teacher's screen. A name is
-- safe to publish; nothing else about them is.
create or replace function public.blurter(p_code text)
returns table (player_id uuid, player_name text)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p.id, p.name
  from public.games g
  join public.players p on p.id = g.blurted_by
  where g.code = upper(trim(p_code)) and g.phase = 'blurt_claimed';
$$;

grant execute on function public.blurt(uuid) to anon, authenticated;
grant execute on function public.judge_blurt(uuid, boolean) to anon, authenticated;
grant execute on function public.blurter(text) to anon, authenticated;
