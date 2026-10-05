-- Light is the default theme now, everywhere.
--
-- /host sends the teacher's choice to a room as soon as it opens, so this only
-- decides the moment before that lands, and any room whose host page never
-- sends it. Rooms already open keep whatever they have.

alter table public.games alter column theme set default 'light';
