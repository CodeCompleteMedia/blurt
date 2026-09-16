# blurt

A live classroom quiz. Questions go on the projector, answers come in on phones,
scores go up on the wall between rounds.

```sh
npm install
vercel env pull .env.local --yes   # VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
npm run dev                        # http://localhost:5173
npm test                           # clock and router
npm run verify:db                  # the security properties, against the real database
```

## The three surfaces

| Path    | Who       | What it shows                                              |
| ------- | --------- | ---------------------------------------------------------- |
| `/`     | student   | Room code, then name                                        |
| `/play` | student   | Four shapes and nothing else — no question text on a phone  |
| `/host` | projector | Room code, question, countdown, distribution, leaderboard   |

Open `/host` and it opens a room. Space advances, `R` starts a new room. A
question that runs out of time locks itself.

## Where the rules live

**In the database, not here.** The students have devtools, so the anon key in
the bundle is assumed public. Every rule is a `SECURITY DEFINER` function in
`supabase/migrations/0002_functions.sql`, and no table is writable by the anon
key.

Five things are never taken from a client:

| | Why |
| --- | --- |
| the correct answer | withheld by `current_question` until the phase is `results` |
| elapsed time | computed from `now() - question_started_at` inside `submit_answer` |
| the score | computed alongside it, never sent by the client |
| player identity | a seat token the database issued at join |
| host authority | a host token kept off the anon-readable `games` row |

`submit_answer` takes a seat token and a choice. That is the whole payload.

Secrets live in their own tables (`game_secrets`, `player_secrets`) because
`games` and `players` must stay anon-readable for Realtime to push to them.

## Client layout

- `src/lib/api.js` — every call the app is allowed to make, one per database
  function. It can ask; it cannot decide.
- `src/lib/clock.js` — countdowns derive from the server's `question_started_at`
  so every screen agrees, with a fallback for a device whose clock is wrong.
- `src/lib/session.js` — the host token or the seat token, in localStorage.
  Refreshing the projector resumes the same room.
- `src/lib/supabase.js` — one client. Missing keys render a setup message rather
  than a blank screen.

Updates arrive over Realtime, with a poll underneath: school networks block and
idle out websockets, and a projector that silently stops advancing mid-lesson is
the worst failure this app has.

## Changing the schema

```sh
npx supabase db push     # apply migrations
npm run verify:db        # 14 checks, as a student would see them
```

Run the second one after every migration. The policies are right today; the risk
is the later change that quietly loosens one. A convenience `select` on
`questions` would hand every phone the answer key, and nothing in `npm test`
would notice.
