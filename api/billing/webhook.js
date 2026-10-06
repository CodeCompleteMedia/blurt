// POST /api/billing/webhook — called by Stripe, not by the app.
//
// The signature is checked against the raw body before anything is read from
// it. After that an event is only a nudge: whatever it says, the customer's
// subscription is re-read from Stripe and copied into teacher_plans (see
// syncCustomer), which is why nothing here stores event ids or compares dates.

import { json, syncCustomer } from '../_lib/billing.js'
import { StripeError, verifyWebhook } from '../_lib/stripe.js'

const WATCHED = new Set([
  'checkout.session.completed',
  'customer.subscription.created',
  'customer.subscription.updated',
  'customer.subscription.deleted',
  'customer.subscription.paused',
  'customer.subscription.resumed',
  'invoice.paid',
  'invoice.payment_failed',
])

export async function POST(request) {
  let event
  try {
    event = verifyWebhook(await request.text(), request.headers.get('stripe-signature'), process.env.STRIPE_WEBHOOK_SECRET)
  } catch (error) {
    if (error instanceof StripeError) return json({ error: error.message }, 400)
    console.error(error)
    return json({ error: 'not configured' }, 500)
  }

  if (!WATCHED.has(event.type)) return json({ received: true })

  const object = event.data?.object ?? {}
  const customer = typeof object.customer === 'string' ? object.customer : object.customer?.id
  if (!customer) return json({ received: true })

  try {
    // Checkout carries the teacher's id, which settles whose customer this is
    // even if the row written at checkout time has gone missing.
    await syncCustomer(customer, event.type === 'checkout.session.completed' ? object.client_reference_id : undefined)
  } catch (error) {
    console.error(error)
    // A customer deleted in Stripe has nothing left to mirror; anything else
    // may be a blip, and a 500 asks Stripe to try again later.
    if (error instanceof StripeError && error.code === 'resource_missing') return json({ received: true })
    return json({ error: 'try again' }, 500)
  }
  return json({ received: true })
}
