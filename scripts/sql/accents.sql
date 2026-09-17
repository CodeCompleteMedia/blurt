\pset pager off
select typed, public.answer_key(typed) = public.answer_key('Patiño School of Entrepreneurship') as matches
from (values ('patino school of entrepreneurship'), ('Patiño School of Entrepreneurship'),
             ('PATINO SCHOOL OF ENTREPRENEURSHIP.'), ('patino school'), ('the patino school of entrepreneurship')) v(typed);
select public.answer_key('Łukasz Dvořák') as folded;
insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \g /dev/null
select public.copy_sample_quiz() as quiz \gset
select count(*) filter (where code ~ '[QO0I1]') as codes_with_a_confusable_letter, count(*) as of
from (select (public.create_game(:'quiz')).code from generate_series(1, 300)) c;
