\set ON_ERROR_STOP off
\pset pager off
insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \g /dev/null
select public.copy_sample_quiz() as quiz \gset
select code, host_token from public.create_game(:'quiz') \gset
select public.update_game_settings(:'host_token', false) \g /dev/null
select player_id, player_token from public.join_game(:'code', 'Ana') \gset a_
select player_id, player_token from public.join_game(:'code', 'Ben') \gset b_
select player_id, player_token from public.join_game(:'code', 'Cara') \gset c_

-- correct answers: 1, 1, 2, 1, 1
-- q1 everyone right; q2 everyone wrong the SAME way (a bad question);
-- q3 they scatter (a hard one); q4 only Ana answers. Game abandoned before q5.
select public.advance_game(:'host_token') \g /dev/null
select public.submit_answer(:'a_player_token', 1) \g /dev/null
select public.submit_answer(:'b_player_token', 1) \g /dev/null
select public.submit_answer(:'c_player_token', 1) \g /dev/null

select public.advance_game(:'host_token') \g /dev/null
select public.submit_answer(:'a_player_token', 3) \g /dev/null
select public.submit_answer(:'b_player_token', 3) \g /dev/null
select public.submit_answer(:'c_player_token', 3) \g /dev/null

select public.advance_game(:'host_token') \g /dev/null
select public.submit_answer(:'a_player_token', 2) \g /dev/null
select public.submit_answer(:'b_player_token', 0) \g /dev/null
select public.submit_answer(:'c_player_token', 1) \g /dev/null

select public.advance_game(:'host_token') \g /dev/null
select public.submit_answer(:'a_player_token', 1) \g /dev/null
select public.advance_game(:'host_token') \g /dev/null
select public.advance_game(:'host_token') \g /dev/null

select '--- hardest first, and question 5 is absent because it was never asked ---' as t;
select q_position, percent_correct, answered, left(q_text, 30) as question,
       common_wrong, common_wrong_count
from public.game_report((select id from public.games where code = :'code'));

select '--- per student ---' as t;
select player_name, place, score > 0 as scored, answered, correct, best_streak, missed
from public.game_players((select id from public.games where code = :'code'));

select '--- the summary knows it was abandoned four questions in ---' as t;
select quiz_title, finished, players, questions_asked, questions_total
from public.game_summary((select id from public.games where code = :'code'));

select '--- it appears in the list of games played ---' as t;
select code, players, questions_asked, finished, top_name from public.my_games();

select '--- another teacher can see none of it ---' as t;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false) \g /dev/null
select count(*) as their_games from public.my_games();
select public.game_report((select id from public.games where code = :'code'));
select public.game_players((select id from public.games where code = :'code'));
select public.delete_game((select id from public.games where code = :'code'));
