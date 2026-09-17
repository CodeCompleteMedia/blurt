-- What the editor needs beyond plain row access: reordering, and somewhere to
-- put pictures.

-- Reordering rewrites every position at once. It has to be one statement — the
-- unique (quiz_id, position) constraint is deferrable precisely so the check
-- waits for the end of it — and a browser cannot send one statement that sets
-- forty rows to forty different values. So it lives here.
create or replace function public.reorder_questions(p_quiz_id uuid, p_ids uuid[])
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.quizzes z where z.id = p_quiz_id and z.owner_id = auth.uid()
  ) then
    raise exception 'that is not your quiz' using errcode = 'insufficient_privilege';
  end if;

  -- Every question, exactly once. A partial list would leave two questions
  -- fighting over a position, or one stranded past the end.
  if (select count(*) from public.questions q where q.quiz_id = p_quiz_id)
       <> coalesce(array_length(p_ids, 1), 0)
     or exists (
       select 1 from unnest(p_ids) as i(id)
       where not exists (select 1 from public.questions q where q.id = i.id and q.quiz_id = p_quiz_id)
     )
     or (select count(distinct i.id) from unnest(p_ids) as i(id)) <> coalesce(array_length(p_ids, 1), 0)
  then
    raise exception 'that is not the full list of questions' using errcode = 'check_violation';
  end if;

  update public.questions q
  set position = o.ord - 1
  from unnest(p_ids) with ordinality as o(id, ord)
  where q.id = o.id and q.quiz_id = p_quiz_id;
end;
$$;

grant execute on function public.reorder_questions(uuid, uuid[]) to authenticated;

-- ------------------------------------------------------------------ images ---

-- Public to read, because the wall is not signed in and has to show them. A
-- picture can give away the question a little early to someone who guesses its
-- URL; it cannot give away the answer. Writing is fenced to a folder named after
-- the teacher's own id, so one account cannot overwrite another's.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('question-images', 'question-images', true, 2097152,
        array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do nothing;

create policy "teachers add their own question images"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'question-images' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "teachers replace their own question images"
  on storage.objects for update to authenticated
  using (bucket_id = 'question-images' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "teachers remove their own question images"
  on storage.objects for delete to authenticated
  using (bucket_id = 'question-images' and (storage.foldername(name))[1] = auth.uid()::text);
