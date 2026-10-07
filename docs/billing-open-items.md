# Billing: where it stands and what is left

Written 6 October 2026, after the first day of testing Stripe sign-up. Times are UTC.

## What is live

- **Database:** migrations `0034` (plans and limits) and `0035` (Free as a demo) are applied to production.
- **Code:** commits `46eb54b` and `2479cb7` are deployed at `www.blurt.it.com`.
- **Free plan:** 3 games ever, up to 40 students, the sample quiz plus one of your own, reports kept, 1 paired display, no export.
- **Teacher plan:** $8 a month or $72 a year. Unlimited games and quizzes, 60 students, 10 displays, export.
- **Comped accounts:** `matthew@quiqlabs.com` and `matthew+blurt@quiqlabs.com` have the Teacher plan without a subscription.

## What has been proven

- `matthew+signup1@quiqlabs.com` signed up locally, paid in the Stripe sandbox, and the database shows an active subscription.
- The live database refuses the plan tables and helper functions to the public key.
- The deployed webhook accepts a request signed with the production secret, at the `www` address.

## Blockers before taking real payments

### 1. Sign-up email is limited to about two an hour

Supabase's built-in sender refused the third sign-up of the hour with "email rate limit exceeded" (emails went out at 20:27 and 20:33; the next attempt failed). Real teachers will hit this as soon as three sign up in an hour.

- [ ] Create an account with a transactional sender (Resend, Postmark or Amazon SES) and verify `blurt.it.com`.
- [ ] Supabase → Authentication → Emails → SMTP Settings: enter the sender's host, port, username and password, with a from-address such as `hello@blurt.it.com`.
- [ ] Supabase → Authentication → Rate Limits: raise the email limit.

Menu names are from memory and may have moved.

### 2. The live webhook address redirects

The endpoint registered in live Stripe is `https://blurt.it.com/api/billing/webhook`. The bare domain answers 308 to `www`, and Stripe does not follow redirects, so no live event will arrive.

- [ ] In live Stripe, change the endpoint URL to `https://www.blurt.it.com/api/billing/webhook`.
- [ ] Send a test event from that page. 200 means the secret matches; 400 "bad signature" means the secret in Vercel is for a different endpoint.

### 3. The Customer Portal has no saved settings

Neither the sandbox nor live Stripe had a portal configuration when checked, so **Manage billing** will fail.

- [ ] Sandbox: Settings → Billing → Customer portal. Enable cancelling and switching between monthly and yearly, then save.
- [ ] Live: the same, separately.

### 4. Production is on live Stripe keys

Vercel's Production environment uses a live restricted key (`rk_live…`) and live prices. A payment on `www.blurt.it.com` charges a real card, and test cards are declined there.

- [ ] Decide whether production stays live now, or uses the sandbox until the items above are done.
- [ ] If it stays live, confirm the restricted key can write Customers, Checkout Sessions and Customer portal sessions, and read Subscriptions. This has not been tested: nothing has been created with the live key.

### 5. Confirmation links from the live site go to `localhost:3000`

Checked by asking Supabase where a link may land (no email sent). `http://localhost:5173/host` is allowed, with or without `?plan=`. Every production address is refused and replaced by the project's Site URL, which is still `http://localhost:3000`. A teacher who signs up on `www.blurt.it.com` gets a confirmation link to a server that does not exist.

- [ ] Supabase → Authentication → URL Configuration: set **Site URL** to `https://www.blurt.it.com`.
- [ ] Add `https://www.blurt.it.com/**` to **Redirect URLs**. The wildcard matters: the link now carries `?plan=month` or `?plan=year`, and an exact `/host` entry would not match it.

## Uncommitted work, waiting on a look

Three changes are in the working tree and not deployed. All build cleanly and the unit tests pass. None has been seen in a browser by anyone but you.

- **The confirmation link goes on to payment by itself** (`AuthGate.svelte`, `auth.svelte.js`, `TeacherShell.svelte`, `billing.svelte.js`). After "Create account" there is a "Check your inbox" screen that says the page can be closed. The link in the email carries the plan, so whichever browser opens it goes to Checkout and then into the app. Only one tab goes to Checkout if two end up signed in. Seen working locally on 6 October with the plan remembered in the browser; the plan-in-the-link version has not been through a real sign-up yet.
- **Monthly / Yearly switch on the sign-up card** (`AuthGate.svelte`), with the saving spelled out ($96 against $72, saves $24).
- **Free against Teacher table in Plan & billing** (`PlanSheet.svelte`), with the teacher's own usage in the Free column.

- [ ] Test a fresh sign-up from the Teacher button once an email slot is free (the first frees about 21:27).
- [ ] Look at the sign-up card at `http://localhost:5173/host?plan=month` and at Plan & billing on a Free account.
- [ ] Commit and push.

## Why `signup2` never reached payment

`matthew+signup2@quiqlabs.com` was created, confirmed and signed in within one minute, and no Stripe customer was ever made for it. The confirmation link signed in somewhere the plan choice was not available: until today's uncommitted change, the choice was remembered only in the browser and site the sign-up started on. The likely cause is the link landing on a different address from the one the sign-up began on.

See blocker 5: the production addresses are not on the allow-list.

## Smaller things

- **Product name.** Stripe calls the product "blurt Pro"; the site calls the plan "Teacher". Teachers see Stripe's name on Checkout and receipts.
- **Plan name.** "Free" now means three games. Renaming it (for example "Try it") is undecided.
- **Preview deployments.** There is no sandbox webhook endpoint, so a Vercel preview cannot receive Stripe events. Local testing uses `stripe listen` instead.
- **Stripe Tax** is off. Set `STRIPE_AUTOMATIC_TAX=1` in Vercel once it is configured in Stripe.
- **`.env.local`** has the Production block commented out so local dev uses the sandbox. Keep it that way.
- **Test accounts** `matthew+signup1`, `+signup2` and `+signup3` exist in production. `signup1` holds a sandbox customer id; delete all three from `/admin` when finished (cancel `signup1`'s sandbox subscription first, or the delete is refused).
- **The admin page's Stripe link** uses the standard dashboard address, which may not open sandbox customers.

## Local testing, for reference

```
npm run dev
stripe listen --forward-to localhost:5173/api/billing/webhook --all-snapshot
```

Sandbox cards: `4242 4242 4242 4242` pays; `4000 0000 0000 0341` attaches and then fails when charged, which is how to see a failed renewal.
