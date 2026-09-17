-- Three kinds of question, and the shapes the database refuses to store.
--
-- The constraints matter more than they look: a typed question saved with no
-- accepted answers is unanswerable, and it got through once because a CHECK
-- only rejects false and `array_length` of an empty array is NULL.
--
-- Note the explicit owner_id. This file used to insert an ownerless quiz and
-- then call create_game, which requires ownership — with ON_ERROR_STOP off, it
-- is not clear the room was ever opened.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x

insert into public.quizzes (id, title, owner_id) values
  ('22222222-2222-2222-2222-222222222222', 'Kinds', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
insert into public.questions (quiz_id, position, kind, text, choices, correct_index, accepted, seconds) values
  ('22222222-2222-2222-2222-222222222222', 0, 'truefalse', 'CSS stands for Cascading Style Sheets.', array['True','False'], 0, null, 15),
  ('22222222-2222-2222-2222-222222222222', 1, 'text', 'Which tag makes an ordered list?', null, null, array['<ol>', 'ordered list'], 20),
  ('22222222-2222-2222-2222-222222222222', 2, 'choice', 'Three options only', array['a','b','c'], 2, null, 15);

do $$
declare stored boolean;
begin
  -- Each of these is a question a teacher could save by accident and only
  -- discover with thirty people watching.
  stored := false;
  begin
    insert into public.questions (quiz_id, position, kind, text, choices, correct_index)
    values ('22222222-2222-2222-2222-222222222222', 9, 'choice', 'correct index past the end', array['a','b'], 3);
    stored := true;
  exception when others then null; end;
  if stored then raise exception 'stored a question whose correct answer is off the end of its choices'; end if;

  stored := false;
  begin
    insert into public.questions (quiz_id, position, kind, text, accepted)
    values ('22222222-2222-2222-2222-222222222222', 9, 'text', 'no accepted answers', array[]::text[]);
    stored := true;
  exception when others then null; end;
  if stored then raise exception 'stored a typed question with no answer that could ever be right'; end if;

  stored := false;
  begin
    insert into public.questions (quiz_id, position, kind, text, choices, correct_index)
    values ('22222222-2222-2222-2222-222222222222', 9, 'truefalse', 'relabelled', array['Yes','No'], 0);
    stored := true;
  exception when others then null; end;
  if stored then raise exception 'stored a true/false question relabelled Yes/No'; end if;

  raise notice 'ok  three unanswerable question shapes refused at the table';
end $$;

do $$
declare target text := public.answer_key('<ol>'); v record;
begin
  for v in select * from (values
    ('<ol>',  true),   -- punctuation is dropped, so this is just "ol"
    ('  OL ', true),   -- case and surrounding space
    ('ol.',   true),
    ('the ol', true),  -- a leading article is dropped on purpose
    ('<OL >', true),
    ('ul',    false),  -- forgiving about typing, not about spelling
    ('oll',   false)
  ) t(typed, should_match) loop
    if (public.answer_key(v.typed) = target) <> v.should_match then
      raise exception '"%" becomes "%" and should % "<ol>"',
        v.typed, public.answer_key(v.typed),
        case when v.should_match then 'match' else 'differ from' end;
    end if;
  end loop;
  raise notice 'ok  typed answers forgive case, space and punctuation, but not spelling';
end $$;

do $$
declare
  g record; rosa record; dev record; bex record; r record;
  n int; refused boolean; wall_rows int;
begin
  select * into g from public.create_game('22222222-2222-2222-2222-222222222222');
  if g.code is null then raise exception 'no room was opened'; end if;
  perform public.update_game_settings(g.host_token, false);
  select * into rosa from public.join_game(g.code, 'Rosa');
  select * into dev  from public.join_game(g.code, 'Dev');
  select * into bex  from public.join_game(g.code, 'Bex');

  -- q1, true/false: exactly two choices, and nothing outside them.
  perform public.advance_game(g.host_token);
  select * into r from public.my_seat(rosa.player_token);
  if r.question_kind <> 'truefalse' or r.choice_count <> 2 then
    raise exception 'the phone was told kind=% with % choices', r.question_kind, r.choice_count;
  end if;

  refused := false;
  begin perform public.submit_answer(rosa.player_token, 2);
  exception when others then refused := true; end;
  if not refused then raise exception 'a third choice was accepted on a true/false question'; end if;

  refused := false;
  begin perform public.submit_text_answer(rosa.player_token, 'True');
  exception when others then refused := true; end;
  if not refused then raise exception 'a typed answer was accepted on a true/false question'; end if;

  perform public.submit_answer(rosa.player_token, 0);
  perform public.submit_answer(dev.player_token, 1);
  perform public.submit_answer(bex.player_token, 0);
  select count(*) into n from public.distribution(g.code);
  if n <> 2 then raise exception 'the true/false distribution has % columns, expected 2', n; end if;

  -- q2, typed: the phone draws a text box, and the wall is given no choices and
  -- no answer while the question is still open.
  perform public.advance_game(g.host_token);
  select * into r from public.my_seat(rosa.player_token);
  if r.question_kind <> 'text' then
    raise exception 'the phone was told kind=% on a typed question', r.question_kind;
  end if;
  select * into r from public.current_question(g.code);
  if r.q_kind <> 'text' or r.q_choices is not null or r.q_answer is not null then
    raise exception 'the wall got kind=% choices=% answer=%', r.q_kind, r.q_choices, r.q_answer;
  end if;

  refused := false;
  begin perform public.submit_answer(rosa.player_token, 0);
  exception when others then refused := true; end;
  if not refused then raise exception 'a tapped choice was accepted on a typed question'; end if;

  perform public.submit_text_answer(rosa.player_token, '  OL ');
  perform public.submit_text_answer(dev.player_token, 'ul');
  perform public.submit_text_answer(bex.player_token, 'fuck this');

  -- Rosa typed it with stray case and spaces and is still right; Dev is not.
  if not (select a.correct from public.answers a
          where a.player_id = rosa.player_id and a.question_index = 1) then
    raise exception '"  OL " was marked wrong against "<ol>"';
  end if;
  if (select a.correct from public.answers a
      where a.player_id = dev.player_id and a.question_index = 1) then
    raise exception '"ul" was marked right against "<ol>"';
  end if;

  -- The wall shows what was typed, minus what should not go on a wall in front
  -- of a class.
  select count(*) into wall_rows from public.text_distribution(g.code);
  if exists (select 1 from public.text_distribution(g.code) td
             where td.answer_text ilike '%fuck%') then
    raise exception 'the projector was about to show a slur to the room';
  end if;
  if wall_rows < 1 then raise exception 'the wall showed nothing that was typed'; end if;

  -- q3, three options: the distribution has three columns, not four.
  perform public.advance_game(g.host_token);
  refused := false;
  begin perform public.submit_answer(rosa.player_token, 3);
  exception when others then refused := true; end;
  if not refused then raise exception 'a fourth choice was accepted on a three-option question'; end if;

  perform public.submit_answer(rosa.player_token, 2);
  perform public.submit_answer(dev.player_token, 2);
  perform public.submit_answer(bex.player_token, 0);
  select count(*) into n from public.distribution(g.code);
  if n <> 3 then raise exception 'the distribution has % columns, expected 3', n; end if;

  raise notice 'ok  three kinds: the phone, the wall and the distribution each get the right shape';
end $$;
