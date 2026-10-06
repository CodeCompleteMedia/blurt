// The server's side of billing: who is asking, and copying what Stripe says
// about them into the one table the database trusts.
//
// This is the only code in blurt that holds the service role key. It must
// never be imported from src/, and none of its env vars may start with VITE_.

import { createClient } from '@supabase/supabase-js'
import { StripeError, pickSubscription, planRow, stripe } from './stripe.js'

let client
export function admin() {
  const url = process.env.SUPABASE_URL ?? process.env.VITE_SUPABASE_URL
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set')
  client ??= createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } })
  return client
}

export const json = (body, status = 200) => Response.json(body, { status })

/** Where Stripe should send a teacher back to. */
export function site(request) {
  return (process.env.SITE_URL ?? new URL(request.url).origin).replace(/\/+$/, '')
}

/**
 * The teacher a request is from, according to Supabase and not to the request:
 * the token is checked there, and an id in the body would be believed by nobody.
 */
export async function teacherFrom(request) {
  const token = (request.headers.get('authorization') ?? '').replace(/^Bearer\s+/i, '')
  if (!token) return null
  const { data, error } = await admin().auth.getUser(token)
  if (error || !data?.user) return null
  return data.user
}

export async function planOf(userId) {
  const { data, error } = await admin().from('teacher_plans').select('*').eq('user_id', userId).maybeSingle()
  if (error) throw new Error(error.message)
  return data
}

/**
 * Make the teacher's row say what Stripe says now.
 *
 * Every webhook ends here, and none of them is believed for its contents: an
 * event only says "look at this customer", and the subscription is read fresh.
 * That is what makes retries, duplicates and out-of-order deliveries harmless.
 * Applying the same answer twice changes nothing, and the answer is never
 * older than the event that prompted it.
 */
export async function syncCustomer(customerId, userId) {
  const { data: subscriptions } = await stripe('GET', '/subscriptions', {
    customer: customerId,
    status: 'all',
    limit: 20,
  })

  let owner = userId
  if (!owner) {
    const { data } = await admin()
      .from('teacher_plans')
      .select('user_id')
      .eq('stripe_customer_id', customerId)
      .maybeSingle()
    owner = data?.user_id
  }
  if (!owner) {
    // A customer blurt has no row for: fall back on the id written on it at
    // creation. A customer made by hand in the dashboard has none, and is
    // nobody's plan.
    const customer = await stripe('GET', `/customers/${customerId}`)
    owner = customer.metadata?.user_id
  }
  if (!owner) return null

  const row = {
    user_id: owner,
    stripe_customer_id: customerId,
    ...planRow(pickSubscription(subscriptions)),
    updated_at: new Date().toISOString(),
  }
  // `comp` is not in the row, so a gift made by SQL survives every sync.
  const { error } = await admin().from('teacher_plans').upsert(row, { onConflict: 'user_id' })
  if (error) {
    // 23503: the teacher's account has been deleted. Nothing to mirror onto.
    if (error.code === '23503') return null
    throw new Error(error.message)
  }
  return row
}

/** The teacher's Stripe customer, made on first need. Returns its id. */
export async function ensureCustomer(user) {
  const existing = (await planOf(user.id))?.stripe_customer_id
  if (existing) {
    try {
      await syncCustomer(existing, user.id)
      return existing
    } catch (error) {
      // An id from another Stripe account, which is what every sandbox id
      // becomes on the day the live keys go in. Start again with a new one.
      if (!(error instanceof StripeError) || error.code !== 'resource_missing') throw error
    }
  }

  const customer = await stripe(
    'POST',
    '/customers',
    // The email is the teacher's own. Nothing about a student ever goes here.
    { email: user.email, metadata: { user_id: user.id } },
    // Two tabs upgrading at once get the same customer, not one each.
    { idempotencyKey: `blurt-customer-${user.id}${existing ? `-after-${existing}` : ''}` },
  )
  const { error } = await admin()
    .from('teacher_plans')
    .upsert(
      { user_id: user.id, stripe_customer_id: customer.id, ...planRow(null), updated_at: new Date().toISOString() },
      { onConflict: 'user_id' },
    )
  if (error) throw new Error(error.message)
  return customer.id
}

/** Run a handler, turning anything thrown into an answer a teacher can read. */
export async function answer(work) {
  try {
    return await work()
  } catch (error) {
    console.error(error)
    const ours = error instanceof StripeError && error.status < 500
    return json({ error: ours ? error.message : 'Billing is not available right now. Try again in a minute.' }, 500)
  }
}
