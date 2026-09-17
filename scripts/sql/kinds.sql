\set ON_ERROR_STOP off
\pset pager off
insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);

insert into public.quizzes (id, title) values ('22222222-2222-2222-2222-222222222222', 'Kinds');
insert into public.questions (quiz_id, position, kind, text, choices, correct_index, accepted, seconds) values
  ('22222222-2222-2222-2222-222222222222', 0, 'truefalse', 'CSS stands for Cascading Style Sheets.', array['True','False'], 0, null, 15),
  ('22222222-2222-2222-2222-222222222222', 1, 'text', 'Which tag makes an ordered list?', null, null, array['<ol>', 'ordered list'], 20),
  ('22222222-2222-2222-2222-222222222222', 2, 'choice', 'Three options only', array['a','b','c'], 2, null, 15);

select '--- shapes the database refuses ---' as t;
insert into public.questions (quiz_id, position, kind, text, choices, correct_index) values
  ('22222222-2222-2222-2222-222222222222', 9, 'choice', 'correct index past the end', array['a','b'], 3);
insert into public.questions (quiz_id, position, kind, text, accepted) values
  ('22222222-2222-2222-2222-222222222222', 9, 'text', 'no accepted answers', array[]::text[]);
insert into public.questions (quiz_id, position, kind, text, choices, correct_index) values
  ('22222222-2222-2222-2222-222222222222', 9, 'truefalse', 'relabelled', array['Yes','No'], 0);

select '--- how forgiving the match is ---' as t;
select v as typed, public.answer_key(v) as becomes, public.answer_key(v) = public.answer_key('<ol>') as matches_ol
from (values ('<ol>'), ('  OL '), ('ol.'), ('the ol'), ('<OL >'), ('ul'), ('oll')) t(v);

select code, host_token from public.create_game('22222222-2222-2222-2222-222222222222') \gset
select public.update_game_settings(:'host_token', false);
select player_id, player_token from public.join_game(:'code', 'Rosa') \gset r_
select player_id, player_token from public.join_game(:'code', 'Dev') \gset d_
select player_id, player_token from public.join_game(:'code', 'Bex') \gset b_

select '--- true/false: two choices, a third is refused ---' as t;
select public.advance_game(:'host_token');
select question_kind, choice_count from public.my_seat(:'r_player_token');
select public.submit_answer(:'r_player_token', 2);
select public.submit_text_answer(:'r_player_token', 'True');
select public.submit_answer(:'r_player_token', 0);
select public.submit_answer(:'d_player_token', 1);
select public.submit_answer(:'b_player_token', 0);
select answer_choice, answer_count from public.distribution(:'code');
select q_answer from public.current_question(:'code');

select '--- typed: the phone is told to draw a text box, the wall gets no choices ---' as t;
select public.advance_game(:'host_token');
select question_kind, choice_count from public.my_seat(:'r_player_token');
select q_kind, q_choices is null as no_choices, q_answer is null as answer_withheld from public.current_question(:'code');
select public.submit_answer(:'r_player_token', 0);
select public.submit_text_answer(:'r_player_token', '  OL ');
select public.submit_text_answer(:'d_player_token', 'ul');
select public.submit_text_answer(:'b_player_token', 'fuck this');
select name, score > 0 as scored from public.players order by name;

select '--- the wall shows what was typed, minus what should not be on a wall ---' as t;
select answer_text, answer_count, is_correct from public.text_distribution(:'code');
select q_answer from public.current_question(:'code');

select '--- three-option question: distribution has three columns ---' as t;
select public.advance_game(:'host_token');
select public.submit_answer(:'r_player_token', 3);
select public.submit_answer(:'r_player_token', 2);
select public.submit_answer(:'d_player_token', 2);
select public.submit_answer(:'b_player_token', 0);
select count(*) as columns from public.distribution(:'code');
