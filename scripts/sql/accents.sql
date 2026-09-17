-- Answer matching folds accents, and room codes avoid letters you misread.
--
-- Both came from the user's own room: "patino" was marked wrong against
-- "Patiño" because the old answer_key turned ñ into a space, and the code QPDLQ
-- was read off the projector as QPDLO because Q and O are near-identical in
-- Londrina Solid at forty feet.
\set ON_ERROR_STOP on
\pset pager off

do $$
declare
  target text := public.answer_key('Patiño School of Entrepreneurship');
  v record;
begin
  for v in select * from (values
    ('patino school of entrepreneurship',     true),
    ('Patiño School of Entrepreneurship',     true),
    ('PATINO SCHOOL OF ENTREPRENEURSHIP.',    true),
    -- A leading article is dropped on purpose, so this is the same answer.
    ('the patino school of entrepreneurship', true),
    -- But folding must not make matching loose in general: this is a different
    -- answer, and a student who wrote it has not written the school's name.
    ('patino school',                         false),
    -- ...and only a *leading* article goes, so an interior one still counts.
    ('patino school of the entrepreneurship', false)
  ) t(typed, should_match) loop
    if (public.answer_key(v.typed) = target) <> v.should_match then
      raise exception '"%" should % the school name, but does not', v.typed,
        case when v.should_match then 'match' else 'differ from' end;
    end if;
  end loop;

  if public.answer_key('Łukasz Dvořák') <> 'lukasz dvorak' then
    raise exception 'Łukasz Dvořák folds to "%", expected "lukasz dvorak"',
      public.answer_key('Łukasz Dvořák');
  end if;

  raise notice 'ok  accents fold without making matching loose';
end $$;

insert into auth.users (id) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select public.copy_sample_quiz() as quiz \gset
select set_config('blurt.quiz', :'quiz', false) \gset x

do $$
declare bad int; total int;
begin
  select count(*) filter (where code ~ '[QO0I1]'), count(*) into bad, total
  from (select (public.create_game(current_setting('blurt.quiz')::uuid)).code
        from generate_series(1, 300)) c;

  if total <> 300 then raise exception 'expected 300 codes, got %', total; end if;
  if bad <> 0 then
    raise exception '% of 300 room codes contain a letter that is misread on a projector', bad;
  end if;
  raise notice 'ok  300 room codes, none containing Q O 0 I or 1';
end $$;
