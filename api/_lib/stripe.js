// Stripe, spoken to directly. blurt asks it for five things (a customer, a
// Checkout page, a portal page, a customer's subscriptions, and whether a
// webhook is really from Stripe), which is not enough to earn an SDK.

import { createHmac, timingSafeEqual } from 'node:crypto'

// The statuses the database treats as paid (plan_of, migration 0034). Only
// used here to decide which subscription to mirror; the database decides
// what a status is worth.
const LIVE = ['active', 'trialing', 'past_due']

/** `{ a: { b: [1] } }` as Stripe wants it: `a[b][0]=1`. */
export function form(params, prefix = '', out = new URLSearchParams()) {
  for (const [key, value] of Object.entries(params ?? {})) {
    if (value === undefined || value === null) continue
    const name = prefix ? `${prefix}[${key}]` : key
    if (typeof value === 'object') form(value, name, out)
    else out.append(name, String(value))
  }
  return out
}

export class StripeError extends Error {
  constructor(message, { status, code } = {}) {
    super(message)
    this.status = status
    this.code = code
  }
}

export async function stripe(method, path, params, { idempotencyKey } = {}) {
  const key = process.env.STRIPE_SECRET_KEY
  if (!key) throw new Error('STRIPE_SECRET_KEY is not set')

  const query = method === 'GET' && params ? `?${form(params)}` : ''
  const response = await fetch(`https://api.stripe.com/v1${path}${query}`, {
    method,
    headers: {
      Authorization: `Bearer ${key}`,
      ...(method === 'GET' ? {} : { 'Content-Type': 'application/x-www-form-urlencoded' }),
      ...(idempotencyKey ? { 'Idempotency-Key': idempotencyKey } : {}),
    },
    body: method === 'GET' ? undefined : form(params),
  })
  const body = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new StripeError(body.error?.message ?? `Stripe answered ${response.status}`, {
      status: response.status,
      code: body.error?.code,
    })
  }
  return body
}

/**
 * Whether a webhook body was signed by Stripe, and recently. The signature
 * covers the exact bytes received, so this takes the raw text, never parsed
 * and re-serialised JSON. Returns the event, or throws.
 */
export function verifyWebhook(raw, header, secret, { now = Date.now() / 1000, tolerance = 300 } = {}) {
  if (!secret) throw new Error('STRIPE_WEBHOOK_SECRET is not set')
  const parts = String(header ?? '').split(',').map((part) => part.trim().split('='))
  const timestamp = parts.find(([k]) => k === 't')?.[1]
  const signatures = parts.filter(([k]) => k === 'v1').map(([, v]) => v)
  if (!timestamp || signatures.length === 0) throw new StripeError('unsigned', { status: 400 })

  const expected = createHmac('sha256', secret).update(`${timestamp}.${raw}`).digest()
  // Stripe sends one signature per active secret while a secret is rolled.
  const matches = signatures.some((signature) => {
    const given = Buffer.from(signature, 'hex')
    return given.length === expected.length && timingSafeEqual(given, expected)
  })
  if (!matches) throw new StripeError('bad signature', { status: 400 })
  // A captured request replayed later carries an old timestamp inside the
  // signed part, so it cannot be freshened.
  if (Math.abs(now - Number(timestamp)) > tolerance) throw new StripeError('stale', { status: 400 })

  return JSON.parse(raw)
}

/**
 * The subscription that says what a teacher is paying: a live one if there
 * is one, otherwise the most recent, so a cancellation is mirrored too.
 */
export function pickSubscription(subscriptions) {
  const newestFirst = [...(subscriptions ?? [])].sort((a, b) => b.created - a.created)
  return newestFirst.find((s) => LIVE.includes(s.status)) ?? newestFirst[0] ?? null
}

const iso = (seconds) => (seconds ? new Date(seconds * 1000).toISOString() : null)

/** A subscription as the columns of public.teacher_plans. Null clears them. */
export function planRow(subscription) {
  if (!subscription) {
    return {
      stripe_subscription_id: null,
      status: null,
      billing_interval: null,
      current_period_end: null,
      cancel_at_period_end: false,
    }
  }
  const item = subscription.items?.data?.[0]
  // Stripe moved the period from the subscription onto its items in 2025;
  // which one an account sends depends on its API version, so read both.
  const periodEnd = item?.current_period_end ?? subscription.current_period_end
  return {
    stripe_subscription_id: subscription.id,
    // "Pause payment collection" leaves a subscription `active` while nothing
    // is charged, which would be the Teacher plan for free. Record it as
    // paused, a status the database does not count as paid.
    status: subscription.pause_collection ? 'paused' : subscription.status,
    billing_interval: item?.price?.recurring?.interval ?? null,
    // A subscription set to end shows the day it ends.
    current_period_end: iso(subscription.cancel_at ?? periodEnd),
    cancel_at_period_end: Boolean(subscription.cancel_at_period_end || subscription.cancel_at),
  }
}
