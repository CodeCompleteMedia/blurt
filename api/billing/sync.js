// POST /api/billing/sync
//
// Re-reads the teacher's subscription from Stripe. The app calls it on the
// way back from Checkout or the portal, so the plan is right on the first
// screen even if the webhook is a few seconds behind. It can only ever copy
// what Stripe says, so calling it from the console gains nothing.

import { answer, json, planOf, syncCustomer, teacherFrom } from '../_lib/billing.js'

export function POST(request) {
  return answer(async () => {
    const user = await teacherFrom(request)
    if (!user) return json({ error: 'Sign in first.' }, 401)

    const customer = (await planOf(user.id))?.stripe_customer_id
    if (customer) await syncCustomer(customer, user.id)
    return json({ ok: true })
  })
}
