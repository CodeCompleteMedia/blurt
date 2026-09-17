-- Remove the six-argument update_game_settings.
--
-- `create or replace function` only replaces when the signature matches. Adding
-- the two blurt-penalty arguments in 0014 therefore created a second function
-- beside the first, and a call naming a subset of arguments matches both — so
-- every settings change started failing with "could not choose the best
-- candidate function" while the app looked fine.
--
-- Worth remembering for the next one: changing a function's arguments is a drop,
-- not a replace.

drop function if exists public.update_game_settings(uuid, boolean, boolean, int, int, boolean);
