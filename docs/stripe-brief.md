# Brief: adding Stripe subscriptions to blurt

You are helping implement paid subscriptions with Stripe in **blurt**, a live classroom quiz app. You cannot see the repository, so this brief is your whole picture of it. Treat everything under "Rules that are not negotiable" as hard constraints. Where a product decision is still open, it is listed under "Decisions the owner has not made yet". Ask about those, and never pick an answer silently.

Work in this order:

1. Ask the open product questions.
2. Propose the data model and the end-to-end flow, and wait for agreement.
3. Write the database migration and its SQL check.
4. Write the server endpoints.
5. Write the client changes.
6. Write a test plan the owner can run in Stripe test mode.

Give complete files, with the path for each, not fragments.

---

## 1. What blurt is

A teacher runs a quiz from a laptop. The question shows on a projector (the "wall"), and 20 to 35 students answer on their own phones after joining with a room code and a first name. Students never have accounts.

The namesake mechanic: each question opens with its choices hidden for a few seconds (the "recall window"). The first student to press **BLURT** claims the floor and says the answer out loud; the teacher marks it right or wrong. A right blurt is worth 1,500 points. A wrong one opens the choices to everyone else.

Who uses it:

- **Teachers** have accounts (Supabase Auth, email and password). They write quizzes, host rooms, and read reports afterwards.
- **Students** are anonymous. They hold a seat token issued by the database, nothing else.
- **A platform admin** (the owner) has an `/admin` page with usage stats and the power to suspend or delete a teacher.

Surfaces and routes:

| Route | Who | What |
|---|---|---|
| `/` | public | Landing page, pre-rendered to static HTML at build time, with a room-code box at the top |
| `/join`, `/j/CODE` | students | Join form; `/j/CODE` is what a QR code opens |
| `/play` | students | The phone: a BLURT button, or lettered answer tiles |
| `/present/CODE`, `/wall/<uuid>` | the room | The projector view; no controls |
| `/host` | teacher | Runs a room: roster, answer key, keyboard shortcuts |
| `/edit` | teacher | Quiz editor, including spreadsheet import |
| `/games` | teacher | Reports on past rooms |
| `/admin` | platform admin | Usage, signups, the teacher list; suspend and delete |

## 2. Stack

- **Front end:** Svelte 5 (runes: `$state`, `$derived`, `$effect`, `$props`) with Vite 8. Plain JavaScript with no TypeScript; ESM throughout.
  - It's a single-page app with a tiny router of its own (`src/lib/router.js`), not SvelteKit.
  - Each surface is lazy-loaded as its own chunk. The teacher screens share one chunk, `src/views/Teacher.svelte`, which wraps them in `AuthGate` and `TeacherShell`.
- **Back end:** Supabase (Postgres, Auth, Realtime Broadcast, Storage). `@supabase/supabase-js` v2.
  - **blurt has no server code of its own today.** All game logic lives in Postgres functions. Stripe's webhook will be the first server endpoint.
  - The browser uses the public anon key, and every client call goes through Row Level Security or `SECURITY DEFINER` functions.
- **Hosting:** Vercel, static output from `dist/`.
  - `vercel.json` rewrites `/` to `/index.html` (the pre-rendered landing page) and everything else to `/app.html` (the SPA shell).
  - Real files are served before rewrites. Confirm that `api/` functions are also matched before the catch-all, and adjust `vercel.json` if not.
- **Env vars:** the client reads `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`. Anything prefixed `VITE_` ships in the browser bundle, so server secrets must not use that prefix.
- **Server functions:** plain Vercel Functions in an `api/` folder at the repo root. Use Web-standard handlers (`export async function POST(request) { ... }`), where `await request.text()` gives the raw body that Stripe's signature check needs.

## 3. Rules that are not negotiable

**1. Students have devtools, and so do teachers.** The anon key is assumed extracted from the bundle within one lesson. Nothing a browser sends is trusted: no score, no elapsed time, no answer key, no identity, and no plan.

**2. Server-enforced entitlements.** A plan is enforced by the database, never by hiding a button. Concretely:

- The plan lives in a table that **no client role can write**. Only the webhook writes to it, using the Supabase **service role key**, held only in server env vars.
- Every limit is checked inside the database at the moment of the action:
  - in the `SECURITY DEFINER` function, for actions that go through one
  - in a `BEFORE INSERT` trigger or the RLS policy, for direct table inserts
- **A teacher calling the function directly from the console must hit the same limit as one using the app.**

**3. Never cut off a room that is already running.** A lapsed payment blocks the *next* room or the next new quiz, never the current lesson.

**4. Students stay out of it.** No student data goes to Stripe. Student counts may be used for limits (for example players per room), but never names or answers.

**5. Migrations follow the project's hard-won rules.** Each of these has caused a silent production bug before:

- **Every new function gets explicit permissions, both halves:**
  - `grant execute ... to authenticated` (or `anon, authenticated`) if it is an API
  - `revoke execute ... from public, anon, authenticated` if it is an internal helper

  Postgres grants EXECUTE to PUBLIC by default, and `alter default privileges` does not prevent it. A check fails on any function whose permissions are NULL.
- **New tables** get `alter table ... enable row level security` and `revoke all on <table> from anon, authenticated`. Data is read through functions.
- **`create or replace function` does not replace a function whose arguments changed.** It adds an overload. Drop the old signature first.
- **A CHECK constraint only rejects `false`; NULL passes.** Wrap it in `coalesce(..., false)` where NULL is possible.
- **`games.quiz_id` references `quizzes` with no cascade**, because reports need the quiz. Quizzes are archived (`archived_at`), not deleted.
- **Checks must use at least two teachers.** Any query that joins by position or code needs a fixture with a second teacher, or a missing filter goes unnoticed.

**6. Testing conventions.**

- `npm run check:migrations` rebuilds every migration from an empty throwaway Postgres, with Supabase's `auth`, `storage` and `realtime` schemas stubbed (`scripts/supabase-stubs.sql`). It can also run a `.sql` test file.
- `npm run check:sql` runs every check in `scripts/sql/*.sql`.
  - A check must `raise exception` on a wrong value, not print a table to eyeball.
  - Each block ends with `raise notice 'ok  <what it proved>'`.
  - A check is only real if it fails with its migration moved aside.
- The local auth stub models `auth.users` with:
  - `id`, `email`, `created_at`, `email_confirmed_at`, `last_sign_in_at`, `banned_until`
  - plus `auth.sessions`

  Extend it if you need more, typed as Supabase has it.
- `npm run verify:db` runs about 90 checks against the live project as a test teacher. `npm run load -- 10x30` runs a concurrency test of 10 rooms of 30.

**7. Code style.**

- Comments explain *why*, not what, in plain sentences.
- Error messages are written for a teacher, or a 15-year-old: "that room is full", "that is not your quiz".
- When raising, use Postgres errcodes: `insufficient_privilege`, `check_violation`, `invalid_parameter_value`.

**8. Svelte 5 trap, which has caused four bugs here.** An `$effect` that sets a timer must depend only on primitives (an id, a number, a phase string), never on an object that gets refreshed. The room object is replaced on every 2.5-second poll and every broadcast, and an effect that reads it restarts and cancels its own timer.

**9. Never use the word "Kahoot"**, anywhere in code, copy or comments.

## 4. The database you are extending

Migrations are in `supabase/migrations/`, numbered `0001` to `0033`. **The next one is `0034`.** The owner applies them to production with `npx supabase db push`.

| Table | What it holds |
|---|---|
| `quizzes` | Teacher's quizzes. `owner_id uuid references auth.users on delete cascade default auth.uid()`, `archived_at`. Written directly from the client under RLS policy `quizzes_owner` (`for all to authenticated using (owner_id = auth.uid())`). |
| `questions` | Belongs to a quiz; RLS via the quiz's owner. Direct client inserts. |
| `games` | A room. `owner_id` (on delete set null), `quiz_id` (no cascade), `code`, `phase`, settings columns, `theme`, `created_at`, `closed_at`. Not readable by anon; read through `game_state(code)`. |
| `game_secrets` | The host token per game. Never readable by clients. |
| `players` | A student in a room: `game_id`, `name`, `score`, `joined_at`. Read through `roster(code)`. |
| `player_secrets`, `answers`, `game_questions` | Seat tokens, answers, the snapshot of questions a room was opened with. |
| `walls` | Paired displays, owned by a teacher (`create_wall` allows at most 10). |
| `platform_admins` | The admin list (migration 0033). Filled by SQL only. `assert_platform_admin()` gates the `admin_*` functions. |

Functions to know about:

- **`create_game(p_quiz_id uuid) returns table (code text, host_token uuid)`** is `SECURITY DEFINER`, and opening a room goes only through it.
  - It checks that `auth.uid()` owns the quiz and the quiz has questions.
  - This is **the natural place for a "rooms per month" limit.**
- **`join_game(p_code, p_name)`** caps a room at 60 players (`v_room_cap constant int := 60`).
  - A plan-based "players per room" limit would change this.
  - Note: it counts without locking the room, so a burst of simultaneous joins can overshoot by a few. The owner has accepted this for the 60 cap. Lock the game row (`for update`) if a lower paid limit must be exact.
- **Quiz creation** is a direct insert into `quizzes` (`db.from('quizzes').insert({ title })` in `src/lib/quizzes.js`). A quiz-count limit therefore needs a `BEFORE INSERT` trigger, or a tightened RLS `with check`, not a client check.
- **`copy_sample_quiz()`** gives a new teacher a sample quiz. Decide whether it counts toward a quiz limit.
- **Admin** (0033): `admin_overview()`, `admin_signups(days)`, `admin_teachers()`, `admin_suspend_teacher(user, bool)`, `admin_delete_teacher(user)`.
  - `admin_teachers()` returns one row per teacher. **Add plan, status and the Stripe customer id to it** so `/admin` can show them.
  - Remember to drop and recreate it, since its return type changes.
  - `admin_delete_teacher` should also cancel or flag the Stripe customer, or at least the brief's design should say what happens.

Client modules, all plain JS under `src/lib/`:

- `supabase.js` exports `db`, the client.
- `auth.svelte.js` exports `auth = $state({ ready, user, recovering })`, plus `signIn`, `signUp`, `setPassword` and `signOut`.
- `api.js` holds game calls; `quizzes.js` holds editor calls; `admin.js` holds admin calls.
- Every module throws `new Error(error.message)` on failure.

The teacher's account menu is in `src/components/TeacherShell.svelte`. It's a dropdown with Change password, Student join page, an Appearance switch and Sign out. **Plan & billing** belongs there.

## 5. What to build

### The flow

1. **Checkout.** The teacher chooses Plan & billing, then a plan.
   - The client calls `POST /api/billing/checkout` with the teacher's Supabase access token in `Authorization: Bearer ...`.
   - The function verifies the token with Supabase (`auth.getUser(token)`, using the service role or anon client). Never trust a user id from the body.
   - It finds or creates the Stripe customer, keyed to the Supabase user id via `metadata.user_id`.
   - It creates a Checkout Session in `subscription` mode and returns its URL. The client redirects.
   - Success and cancel URLs return to `/host`, or to a billing page.
2. **Webhook.** `POST /api/billing/webhook` verifies the `Stripe-Signature` header against the raw body with `STRIPE_WEBHOOK_SECRET`. On the relevant events it upserts the teacher's plan row with the service role key:
   - `checkout.session.completed`
   - `customer.subscription.created` / `updated` / `deleted`
   - `invoice.payment_failed` / `invoice.paid`

   It must be **idempotent**, since Stripe retries and can deliver out of order. Store the event id, or compare `subscription.current_period_end` or the event `created` time.
3. **Manage.** Plan & billing also opens the Stripe **Customer Portal** (`POST /api/billing/portal`, same token check), where the teacher changes card, switches interval or cancels. blurt builds no card or invoice UI.
4. **Entitlements.** A database function, for example `plan_of(uid) returns text`, gives the current plan. It applies status, grace period and trial rules, and every gated function or trigger uses it.

### The plan table

A sketch to refine, not a requirement:

- `public.teacher_plans`:
  - `user_id uuid primary key references auth.users on delete cascade`
  - `stripe_customer_id text unique`
  - `stripe_subscription_id text`
  - `plan text`
  - `status text` (mirrors Stripe's `active`, `trialing`, `past_due`, `canceled`, …)
  - `current_period_end timestamptz`
  - `trial_ends_at timestamptz`
  - `updated_at`
- RLS enabled; `revoke all from anon, authenticated`.
- A `my_plan()` function for the teacher's own row, granted to authenticated.
- Only the service role writes. The webhook runs as the service role, which bypasses RLS.

### Server env vars (Vercel, never `VITE_`)

- `STRIPE_SECRET_KEY`
- `STRIPE_WEBHOOK_SECRET`
- `SUPABASE_SERVICE_ROLE_KEY`
- `SUPABASE_URL` (or reuse the `VITE_` URL value)
- Price ids, for example `STRIPE_PRICE_MONTHLY` and `STRIPE_PRICE_YEARLY`

### Client

- A **Plan & billing** item in the account menu, showing the current plan from `my_plan()`, with Upgrade (Checkout) or Manage (Portal).
- **Limit errors raised by the database** appear as plain messages where the action happened, for example "Your free plan includes 3 quizzes. Upgrade to add more."
- **`/admin`** gains plan and status columns, and a link to the customer in the Stripe dashboard (`https://dashboard.stripe.com/customers/<id>`).

### Tests the owner expects

- **A new `scripts/sql/billing.sql`.** With two or more teachers, one paid and one free, it proves:
  - the free teacher hits each limit through the database functions and direct inserts
  - the paid one does not
  - a client role cannot write `teacher_plans`, or read anyone else's row
  - a lapsed plan blocks the next room but not a room already open
- **A test-mode walkthrough** using the Stripe CLI (`stripe listen --forward-to localhost:<port>/api/billing/webhook`):
  - checkout with test card `4242 4242 4242 4242`
  - cancel in the Portal
  - a failed payment with test card `4000 0000 0000 0341`

## 6. Decisions the owner has not made yet

Ask about these before designing around them. The owner's planning doc lists them as open.

1. **Who pays first:** individual teachers by card (the current recommendation), or schools by invoice. School licences with seats and an admin are a later phase. Design the plan row so a school could own it later.
2. **Which limits, and at what numbers.** These are only placeholders:

   | Limit | Free | Paid |
   |---|---|---|
   | Quizzes | 3 | unlimited |
   | Rooms per month | 5 | unlimited |
   | Players per room | 15 | 40+ |
   | Report history | 30 days | all |
   | Paired displays | 1 | unlimited |
   | CSV export | no | yes |

3. **Price, and whether there's a yearly discount.**
4. **Trial:** length, and whether it needs a card. 14 days without a card is the working assumption.
5. **Grace period on a failed payment,** for example a few days before limits apply.
6. **US only, or international.** Stripe Tax for sales tax and VAT, or a merchant of record instead (Paddle, Lemon Squeezy). If the owner picks a merchant of record, most of the Stripe-specific parts change.
7. **What happens to a lapsed teacher's quizzes and reports:** kept read-only, or deleted after a time.
8. **Whether existing accounts are grandfathered,** and onto which plan.
9. **Whether light/dark, the doodle wall and the music are free for everyone,** or paid features.

## 7. Out of scope here

- School and district licences, seats, invoicing and purchase orders, and single sign-on. That's a later phase.
- Student-privacy policies and agreements. Separate work, but the billing design must not send student data anywhere.
- Rebuilding anything Stripe's hosted Checkout and Portal already do.
