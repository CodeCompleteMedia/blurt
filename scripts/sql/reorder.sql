-- Reordering questions is all-or-nothing, and belongs to the quiz's owner.
--
-- The positions carry a deferrable unique constraint, so a reorder is one
-- statement that would otherwise collide with itself halfway through.
\set ON_ERROR_STOP on
\pset pager off

insert into auth.users (id) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"}', false) \gset x
select public.copy_sample_quiz() as quiz \gset
select set_config('blurt.quiz', :'quiz', false) \gset x

do $$
declare
  q uuid := current_setting('blurt.quiz')::uuid;
  forward uuid[];
  reversed uuid[];
  now_order uuid[];
  refused boolean;
begin
  select array_agg(id order by position) into forward from public.questions where quiz_id = q;
  select array_agg(id order by position desc) into reversed from public.questions where quiz_id = q;

  perform public.reorder_questions(q, reversed);
  select array_agg(id order by position) into now_order from public.questions where quiz_id = q;
  if now_order <> reversed then
    raise exception 'reversing all five did not take';
  end if;
  -- Positions must still be 0..4 with no gap and no duplicate, which is the
  -- thing the deferrable constraint exists to protect.
  if (select array_agg(position order by position) from public.questions where quiz_id = q)
     <> array[0,1,2,3,4] then
    raise exception 'positions are no longer 0..4 after a reorder';
  end if;

  -- A partial list would leave the rest at positions that no longer make sense.
  refused := false;
  begin perform public.reorder_questions(q, reversed[1:3]);
  exception when others then refused := true; end;
  if not refused then raise exception 'a three-of-five reorder was accepted'; end if;
  select array_agg(id order by position) into now_order from public.questions where quiz_id = q;
  if now_order <> reversed then
    raise exception 'the refused partial reorder still moved questions';
  end if;

  perform set_config('request.jwt.claims',
    '{"sub":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"}', false);
  refused := false;
  begin perform public.reorder_questions(q, forward);
  exception when others then refused := true; end;
  if not refused then raise exception 'another teacher reordered my quiz'; end if;
  select array_agg(id order by position) into now_order from public.questions where quiz_id = q;
  if now_order <> reversed then
    raise exception 'another teacher''s refused reorder still moved questions';
  end if;

  raise notice 'ok  all five reverse; a partial list and another teacher both refused, changing nothing';
end $$;
