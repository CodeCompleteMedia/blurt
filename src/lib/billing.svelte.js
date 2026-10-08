// The teacher's plan, and the three trips to Stripe. This file decides nothing:
// the plan is read from the database, which is also what enforces it, and the
// endpoints under /api/billing work out who is asking from the session token.
// Changing anything here from the console changes what the page says, not what
// the account can do.

import { db } from './supabase.js'

// null until asked. A fresh object on every refresh, so effects that care
// should read a field off it, not the object.
export const billing = $state({ plan: null })

export async function refreshPlan() {
  const { data, error } = await db.rpc('my_plan')
  if (error) throw new Error(error.message)
  billing.plan = data?.[0] ?? null
  return billing.plan
}

async function call(path, body = {}) {
  const { data } = await db.auth.getSession()
  const response = await fetch(`/api/billing/${path}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${data.session?.access_token ?? ''}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  const result = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(result.error ?? 'Billing is not available right now. Try again in a minute.')
  return result
}

/**
 * Off to Stripe Checkout. Resolves to false if the page is leaving, or true
 * if there was nothing to buy because this account already pays.
 */
export async function startCheckout(interval) {
  const { url, already } = await call('checkout', { interval })
  if (already) return true
  window.location.assign(url)
  return false
}

export async function openPortal() {
  const { url } = await call('portal')
  window.location.assign(url)
}

/** Ask the server to re-read Stripe, then read the result. */
export async function syncPlan() {
  await call('sync')
  return refreshPlan()
}

/**
 * Read the plan, and if what the database holds about a subscription is more
 * than a day old, have the server read Stripe again first.
 *
 * Normally the webhook keeps the row current and this does nothing. It is for
 * the day the webhook does not arrive: the database stops believing a
 * subscription a few days after its paid period (migration 0036), and without
 * this a teacher whose renewal went through unseen would be dropped to Free.
 * The server only ever copies what Stripe says, so there is nothing to gain by
 * calling this, or by not calling it.
 */
export async function refreshPlanFromStripeIfStale() {
  const plan = await refreshPlan()
  const DAY = 24 * 60 * 60 * 1000
  const stale = plan?.has_customer && plan.status && Date.now() - new Date(plan.synced_at).getTime() > DAY
  // If Stripe cannot be reached, what the database says stands.
  return stale ? syncPlan().catch(() => plan) : plan
}

// -------------------------------------------------------------- the intent --
// "I want the Teacher plan, yearly", carried from the pricing page through
// sign-up to Checkout. It rides in the address (/host?plan=year), and is also
// kept on the device, because confirming an email address opens a fresh tab
// from a link that carries nothing. A day is long enough to find that email
// and short enough that it does not ambush whoever signs in next week.

const KEY = 'blurt:plan-intent'
const DAY = 24 * 60 * 60 * 1000
const valid = (interval) => (interval === 'month' || interval === 'year' ? interval : null)

/** What the address asks for, if anything. */
export function intentInAddress() {
  return valid(new URLSearchParams(window.location.search).get('plan'))
}

export function rememberIntent(interval) {
  try {
    if (valid(interval)) localStorage.setItem(KEY, JSON.stringify({ interval, at: Date.now() }))
  } catch {
    // Private windows may refuse storage. The teacher can still upgrade from the menu.
  }
}

/** The intent, from the address or the device, without spending it. */
export function peekIntent() {
  const here = intentInAddress()
  if (here) return here
  try {
    const kept = JSON.parse(localStorage.getItem(KEY) ?? 'null')
    return kept && Date.now() - kept.at < DAY ? valid(kept.interval) : null
  } catch {
    return null
  }
}

export function forgetIntent() {
  try {
    localStorage.removeItem(KEY)
  } catch {
    // Nothing was kept, then.
  }
}

/**
 * Whether this tab is the one to go to Checkout. Confirming an email address
 * can leave two tabs signed in at the same moment, the one the link opened and
 * the one that was waiting, and both know what the teacher came to buy. The
 * first to ask gets it; the other just opens the app. Two Checkout pages for
 * one teacher is how someone ends up paying twice.
 */
const CLAIM = 'blurt:checkout-claimed'

export function claimCheckout() {
  try {
    if (Date.now() - Number(localStorage.getItem(CLAIM) ?? 0) < 60 * 1000) return false
    localStorage.setItem(CLAIM, String(Date.now()))
  } catch {
    // No storage, so no second tab could have left a claim either.
  }
  return true
}

/** Back from Stripe: the trip is over, so the next one may start at once. */
export function releaseCheckout() {
  try {
    localStorage.removeItem(CLAIM)
  } catch {
    // Nothing was claimed, then.
  }
}

// --------------------------------------------------------------- the sheet --
// Plan & billing lives in the shell; a page that wants it opened (a report
// asking for an export, say) calls showPlan with a line saying why.

let opener = null
export const onShowPlan = (open) => (opener = open)
export const showPlan = (note) => opener?.(note)
