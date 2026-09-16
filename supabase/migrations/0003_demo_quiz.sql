-- The five starter questions, as data rather than as a hard-coded module.
-- A migration rather than a seed file so `supabase db push` carries it; it is
-- idempotent, and Phase 3 turns quizzes into something the teacher authors.

insert into public.quizzes (id, title, default_seconds)
values ('11111111-1111-1111-1111-111111111111', 'HTML & CSS: the first fortnight', 20)
on conflict (id) do nothing;

insert into public.questions (quiz_id, position, text, choices, correct_index, seconds)
values
  ('11111111-1111-1111-1111-111111111111', 0,
   'Which tag holds everything the visitor actually sees?',
   array['<head>', '<body>', '<title>', '<meta>'], 1, 15),
  ('11111111-1111-1111-1111-111111111111', 1,
   'You want a list where the order matters. Which one?',
   array['<ul>', '<ol>', '<dl>', '<li>'], 1, 15),
  ('11111111-1111-1111-1111-111111111111', 2,
   'In CSS, what does the selector .note actually match?',
   array['The element with id "note"', 'Every <note> element',
         'Every element with class "note"', 'The first note on the page'], 2, 25),
  ('11111111-1111-1111-1111-111111111111', 3,
   'padding is the space...',
   array['outside the border', 'between the content and the border',
         'between two sibling elements', 'around the whole page'], 1, 20),
  ('11111111-1111-1111-1111-111111111111', 4,
   'Which one makes an image accessible to a screen reader?',
   array['title=""', 'alt=""', 'aria-image=""', 'caption=""'], 1, 20)
on conflict (quiz_id, position) do nothing;
