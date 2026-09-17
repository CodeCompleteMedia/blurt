\set ON_ERROR_STOP off
\pset pager off
insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);
select public.copy_sample_quiz() as quiz \gset
select code, host_token from public.create_game(:'quiz') \gset
select public.update_game_settings(:'host_token', false);   -- no recall, to keep this short
select player_id, player_token from public.join_game(:'code', 'Streaky') \gset s_
select player_id, player_token from public.join_game(:'code', 'Skipper') \gset k_
select player_id, player_token from public.join_game(:'code', 'Filler') \gset f_

-- correct answers for the sample quiz: 1, 1, 2, 1, 1
-- Streaky: right, right, right, WRONG, right
-- Skipper: right, (skips), right ...
select public.advance_game(:'host_token');
select public.submit_answer(:'s_player_token', 1); select public.submit_answer(:'k_player_token', 1);
select public.advance_game(:'host_token'); select public.advance_game(:'host_token');  -- locked, results

select '--- q1: first right answer, no run yet ---' as t;
select correct, bonus, streak from public.my_result(:'s_player_token');

select public.advance_game(:'host_token');  -- q2
select public.submit_answer(:'s_player_token', 1);
select public.advance_game(:'host_token'); select public.advance_game(:'host_token');
select '--- q2: two in a row is worth 100; the one who skipped has lost theirs ---' as t;
select 'Streaky' as who, correct, bonus, streak from public.my_result(:'s_player_token')
union all select 'Skipper', correct, bonus, streak from public.my_result(:'k_player_token');

select public.advance_game(:'host_token');  -- q3
select public.submit_answer(:'s_player_token', 2); select public.submit_answer(:'k_player_token', 2);
select public.advance_game(:'host_token'); select public.advance_game(:'host_token');
select '--- q3: three in a row is 200; skipping q2 means Skipper starts over ---' as t;
select 'Streaky' as who, correct, bonus, streak from public.my_result(:'s_player_token')
union all select 'Skipper', correct, bonus, streak from public.my_result(:'k_player_token');

select public.advance_game(:'host_token');  -- q4
select public.submit_answer(:'s_player_token', 0);
select public.advance_game(:'host_token'); select public.advance_game(:'host_token');
select '--- q4: a wrong answer ends the run ---' as t;
select correct, bonus, streak from public.my_result(:'s_player_token');

select public.advance_game(:'host_token');  -- q5
select public.submit_answer(:'s_player_token', 1);
select public.advance_game(:'host_token'); select public.advance_game(:'host_token');
select '--- q5: and it begins again from nothing ---' as t;
select correct, bonus, streak from public.my_result(:'s_player_token');

select '--- score is answers plus bonuses, nothing unaccounted for ---' as t;
select p.name, p.score, sum(greatest(a.awarded,0)) + sum(a.bonus) as accounted
from public.players p join public.answers a on a.player_id = p.id
where p.id = :'s_player_id' group by p.name, p.score;

select '--- with the setting off there is no bonus ---' as t;
select code as c2, host_token as h2 from public.create_game(:'quiz') \gset
select public.update_game_settings(:'h2', false, null, null, null, null, null, null, false);
select player_id, player_token from public.join_game(:'c2', 'Plain') \gset p_
select player_id, player_token from public.join_game(:'c2', 'Other') \gset o_
select public.advance_game(:'h2'); select public.submit_answer(:'p_player_token', 1);
select public.advance_game(:'h2'); select public.advance_game(:'h2'); select public.advance_game(:'h2');
select public.submit_answer(:'p_player_token', 1);
select public.advance_game(:'h2'); select public.advance_game(:'h2');
select correct, bonus, streak from public.my_result(:'p_player_token');
