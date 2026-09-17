\set ON_ERROR_STOP off
\pset pager off
insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \g /dev/null
select public.copy_sample_quiz() as quiz \gset
select code, host_token from public.create_game(:'quiz') \gset
select player_id, player_token from public.join_game(:'code', 'Rosa') \gset r_

select '--- the game took a copy of all five questions ---' as t;
select count(*) as copied from public.game_questions where game_id = (select id from public.games where code = :'code');

select public.update_game_settings(:'host_token', false) \g /dev/null
select public.advance_game(:'host_token') \g /dev/null

select '--- now the teacher edits the quiz mid-game, and deletes two questions ---' as t;
update public.questions set text = 'REWRITTEN', correct_index = 3 where quiz_id = :'quiz' and position = 0;
delete from public.questions where quiz_id = :'quiz' and position in (3, 4);

select '--- the room still shows what it opened with ---' as t;
select q_text from public.current_question(:'code');

select '--- and the correct answer is still the one the class was shown ---' as t;
select public.submit_answer(:'r_player_token', 1) \g /dev/null
select correct from public.answers where game_id = (select id from public.games where code = :'code');

select '--- the game is still five questions long, not three ---' as t;
select public.advance_game(:'host_token') \g /dev/null
select public.advance_game(:'host_token') \g /dev/null
select count(*) as steps_to_the_end from (
  select public.advance_game(:'host_token') from generate_series(1, 20)
) x;
select phase, question_index from public.games where code = :'code';

select '--- a game opened after the edit sees the edit ---' as t;
select code as c2, host_token as h2 from public.create_game(:'quiz') \gset
select count(*) as copied from public.game_questions where game_id = (select id from public.games where code = :'c2');
select public.advance_game(:'h2') \g /dev/null
select public.advance_game(:'h2') \g /dev/null
select q_text from public.current_question(:'c2');

select '--- and nobody can read the copy directly ---' as t;
set role anon;
select count(*) from public.game_questions;
reset role;
set role authenticated;
select count(*) from public.game_questions;
