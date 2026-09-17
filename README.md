# blurt

A live classroom quiz. Questions go on the projector, answers come in on phones,
scores go up on the wall between rounds.

```sh
npm install
vercel env pull .env.local --yes   # VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
npm run dev                        # http://localhost:5173
npm test                           # clock and router
npm run verify:db                  # the security properties, against the real database
npm run load                       # 40 phones at once; `npm run load -- 60` for more
npm run check:migrations           # rebuild every migration from an empty Postgres
```

## The five surfaces

| Path             | Who         | What it shows                                                     |
| ---------------- | ----------- | ----------------------------------------------------------------- |
| `/`              | student     | Room code, then name                                               |
| `/play`          | student     | One blurt button, or four shapes — never the question text         |
| `/present/CODE`  | the wall    | Question, countdown, distribution, leaderboard. No controls        |
| `/host`          | the teacher | Live roster, the answer key, and every control. Signed in          |
| `/edit`          | the teacher | Write, reorder, import and illustrate quizzes. Signed in           |

Open `/host` and it opens a room, then press `P` for the projector window.

| Key | |
| --- | --- |
| `Space` | advance |
| `Y` / `N` | judge a blurt |
| `E` | fifteen more seconds on the clock |
| `H` | hold — pause and resume, and the time comes back |
| `S` | settings |
| `P` | projector window |
| `R` | new room (closes this one for everyone) |

Recall and the answer window close themselves. Each roster row has Rename and
Remove; Remove takes two taps because it deletes a score.

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

## Writing quizzes

`/edit` saves as you type. A question that cannot be saved yet says why on its own
card — it never fails quietly on the way out.

Three kinds of question: up to four choices, true or false, and type-the-answer.
A typed answer is forgiven what a marker would forgive — case, spacing,
punctuation, a leading "the" — so `  OL. ` matches `<ol>`. **Spelling is not
forgiven.** A fuzzy match that accepts "mitocondria" also accepts answers that are
simply wrong; a student who loses a point to a typo can argue it with you, and one
who gains a point from a lucky near-miss never will. Give alternatives instead.

What the room typed goes up on the wall at results, through the same filter as
names — a class learns within one question that the answer box is a way onto the
projector.

**Importing.** Paste rows straight out of Google Sheets or Excel (they arrive
tab-separated, which is detected) or pick a `.csv`. Columns are `question, a, b,
c, d, correct, seconds`, in that order or under headers in any order. `correct`
may be a letter, a number, or the answer spelled out. Leave the choices empty and
put `true`/`false` for a true-or-false question, or `answer|another way` for a
typed one. Bad rows are listed by their spreadsheet line and left out; good rows
still come in.

**Pictures** are shrunk in the browser to 1600px before upload. A phone photo is
several megabytes, and the projector's laptop has to fetch it over school wifi at
the instant the question appears.

**Deleting a quiz archives it.** Every game played from a quiz points back at it,
and later reports need the questions a class was actually asked.

## Who is the teacher

Accounts are Supabase Auth, email and password. Only a quiz's owner can read it,
change it, or host it — that last one matters most: the host sees the answer key,
so before ownership existed anyone could open a private room on any quiz and walk
off with it. Students never sign in to anything.

Once your own account exists, **turn off new sign-ups** in Supabase (Authentication
→ Sign In / Providers → "Allow new users to sign up"). A stranger with an account
could only ever see their own quizzes, but there is no reason to let them make one.

`verify:db` and `load` act as a teacher, from `BLURT_TEST_EMAIL` and
`BLURT_TEST_PASSWORD` in `.env.local`. They never create the account themselves.

## In a real room

Phase 3 was about the things that only go wrong with thirty teenagers.

- **A phone that refreshes or locks comes back where it was.** `my_seat` tells it
  whether it has already answered — but not whether it was right; that still
  waits for results.
- **Names are filtered in the database**, so the filter cannot be reached around.
  It undoes the usual disguises (`sh1t`, `fuuuck`, `b!tch`) and refuses anything
  passing as the person in charge. It is there for the lazy attempts. Rename and
  Remove are the answer to the rest — no filter survives a determined
  fourteen-year-old.
- **A room takes sixty players.** Past that it is a script, not a class.
- **Pause hands the time back.** A fire drill costs nobody a point.
- **Load:** sixty simultaneous claims produce exactly one winner, and sixty
  simultaneous answers are all counted, each volley inside about 400ms.

The adversarial pass that opened the phase found internal helper functions
callable with the anon key. Migration `0002` revoked execute "on all functions",
which only ever meant the functions that existed that day — Postgres grants each
new one to `PUBLIC`. Defaults are closed now, so **every new function that is
meant to be an API needs an explicit `grant`**, and `verify:db` checks that the
internal ones refuse.

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

### The name filter turns away some real names

Whole-word matches include `dick`, so a student who goes by Dick cannot join under
that name. Matching those words anywhere instead would block Shital, Nazir,
Pornchai and Cassandra, which is the worse trade. **If it bites:** delete the row
from `blocked_words` — the list is data, not code.

### Anyone with the anon key can list open rooms

`games` and `players` are readable so Realtime can push to them, which means a
curious student can see every room code in use and join another class's game.
Nothing secret leaks, and Remove deals with a visitor. **Worth fixing if** more
than one teacher uses this at once: scope reads to a room the caller has joined.

### Anyone can open a room

`create_game` takes no credential, so a script could create rooms all day. They
cost a row each and affect nobody. **Worth fixing when** accounts exist.
