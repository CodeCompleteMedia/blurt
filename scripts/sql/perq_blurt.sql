\set ON_ERROR_STOP off
\pset pager off
insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);

insert into public.quizzes (id, title) values ('33333333-3333-3333-3333-333333333333', 'Mixed');
insert into public.questions (quiz_id, position, kind, text, choices, correct_index, accepted, seconds, blurt_enabled) values
  ('33333333-3333-3333-3333-333333333333', 0, 'choice', 'Blurtable', array['a','b'], 0, null, 15, true),
  ('33333333-3333-3333-3333-333333333333', 1, 'choice', 'Not blurtable', array['a','b'], 1, null, 15, false),
  ('33333333-3333-3333-3333-333333333333', 2, 'text',   'Typed', null, null, array['x'], 15, false);

select '--- each question opens in the phase it asked for ---' as t;
select code, host_token from public.create_game('33333333-3333-3333-3333-333333333333') \gset
select player_id, player_token from public.join_game(:'code', 'Rosa') \gset r_

select public.advance_game(:'host_token');
select question_index, phase, 'expect recall' as expected from public.games where code = :'code';

select public.advance_game(:'host_token');  -- recall -> question_open
select public.submit_answer(:'r_player_token', 0);
select public.advance_game(:'host_token');  -- results -> q2, blurt off
select question_index, phase, 'expect question_open' as expected from public.games where code = :'code';

select '--- and the floor cannot be claimed on one that opted out ---' as t;
select public.blurt(:'r_player_token') as claimed;

select public.submit_answer(:'r_player_token', 0);
select public.advance_game(:'host_token');  -- results -> q3 (typed, blurt off)
select question_index, phase, q_kind, q_blurt from public.games g, public.host_question(:'host_token') where g.code = :'code';

select '--- the master switch still wins over a question that wants it ---' as t;
select code as c2, host_token as h2 from public.create_game('33333333-3333-3333-3333-333333333333') \gset
select public.update_game_settings(:'h2', false);
select public.advance_game(:'h2');
select question_index, phase, 'expect question_open' as expected from public.games where code = :'c2';

select '--- and with blurting on, question 1 still gets its window ---' as t;
select code as c3, host_token as h3 from public.create_game('33333333-3333-3333-3333-333333333333') \gset
select player_id, player_token from public.join_game(:'c3', 'Dev') \gset d_
select public.advance_game(:'h3');
select public.blurt(:'d_player_token') as claimed;
select phase from public.games where code = :'c3';

select '--- a copied quiz keeps each question''s setting ---' as t;
select public.duplicate_quiz('33333333-3333-3333-3333-333333333333') as copy \gset
select position, kind, blurt_enabled from public.questions where quiz_id = :'copy' order by position;
