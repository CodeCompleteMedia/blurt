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

// --------------------------------------------------------------- the sheet --
// Plan & billing lives in the shell; a page that wants it opened (a report
// asking for an export, say) calls showPlan with a line saying why.

let opener = null
export const onShowPlan = (open) => (opener = open)
export const showPlan = (note) => opener?.(note)
