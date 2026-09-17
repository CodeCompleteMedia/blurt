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

## The four surfaces

| Path             | Who         | What it shows                                                     |
| ---------------- | ----------- | ----------------------------------------------------------------- |
| `/`              | student     | Room code, then name                                               |
| `/play`          | student     | One blurt button, or four shapes — never the question text         |
| `/present/CODE`  | the wall    | Question, countdown, distribution, leaderboard. No controls        |
| `/host`          | the teacher | Live roster, the answer key, and every control                      |

Open `/host` and it opens a room, then press `P` for the projector window.
Space advances, `Y`/`N` judges a blurt, `R` starts a new room. Recall and the
answer window both close themselves.

`/present` holds no credential — it is a screen, not a session, identified by
the room code in its path. The host token lives on `/host` instead, which is the
machine the room cannot see.

## Blurt

A question opens with its **choices hidden**. For a few seconds anyone can hit
one button; the claimant says the answer out loud and the teacher marks it.

- **Right** — 1500 points, more than any tapped answer can be worth.
- **Wrong** — you are out of this question. Everyone else gets the choices.
- **Nobody claims it** — the choices go up and it is an ordinary question.

Recall is the high-value path and recognition is the fallback, which is the
point: it rewards knowing the answer over spotting it.

Claiming the floor is one conditional update, so whoever the database writes
first wins and every later claim matches zero rows. There is no tie to resolve
and no client-supplied timestamp to trust. The network is still a race — same
wifi, and it plays fair.

The wrong-blurt lockout needs no new enforcement: the blurt writes an `answers`
row, and the existing unique index on `(game, player, question)` is what then
refuses their multiple-choice attempt.

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
| the choices, during recall | withheld by `current_question` until the window closes |

That last row is the one that makes recall real. Hiding the choices on screen
would be theatre — a student with the console would read them straight out of
the API. `host_question` is the deliberate exception: the referee has to know
the answer while a student is saying it out loud, and it is gated on the host
token.

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

## Decisions worth revisiting

Things deliberately left out, with what it would cost to put them back. Each one
was a judgement call, not an oversight.

### Extended latin is not bundled

The build ships **basic latin only** (`U+0000-00FF`), which covers é, ñ, ü, ö, å
and ç — most Western European names render entirely in Rubik.

It does **not** cover extended latin (`U+0100+`). A student called Łukasz, Dvořák
or Nguyễn gets those particular letters from the system fallback while the rest of
their name is Rubik. Mixed within one word, that reads as a bug rather than as a
fallback — and it is a student's own name, which is the worst place to look
careless.

**Why it is out:** `rubik-latin-ext-wght-normal.woff2` is another 19KB. Preloaded,
every phone in the room pays for it on every first load, for a handful of glyphs
most classes never type. Loaded but not preloaded, the affected names visibly swap
a beat after the rest of the page.

**To put it back**, in `src/app.css` add a second `@font-face` for
`@fontsource-variable/rubik/files/rubik-latin-ext-wght-normal.woff2`, carrying the
`unicode-range` from `@fontsource-variable/rubik/wght.css` so the browser only
fetches it when an extended character actually appears. Then decide separately
whether `vite.config.js` should preload it — its pattern currently matches every
emitted `.woff2`, so bundling it is enough to preload it, and excluding it is the
extra step.

**Worth reversing if:** a class roster has names that need it. One student is
reason enough.
