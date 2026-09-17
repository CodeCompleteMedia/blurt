\set ON_ERROR_STOP off
\pset pager off
insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false);
select public.copy_sample_quiz() as quiz \gset
select array_agg(id order by position desc) as reversed from public.questions where quiz_id = :'quiz' \gset
select '--- reverse all five in one call ---' as t;
select public.reorder_questions(:'quiz', :'reversed'::uuid[]);
select position, left(text, 34) as text from public.questions where quiz_id = :'quiz' order by position;
select '--- a partial list is refused ---' as t;
select public.reorder_questions(:'quiz', (:'reversed'::uuid[])[1:3]);
select '--- so is someone else ---' as t;
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false);
select public.reorder_questions(:'quiz', :'reversed'::uuid[]);
