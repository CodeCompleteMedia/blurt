// POST /api/billing/checkout  { interval: 'month' | 'year' }
//
// Sends back the address of a Stripe Checkout page for the Teacher plan. The
// card form is Stripe's; blurt never sees a card number.

import { answer, ensureCustomer, json, planOf, site, teacherFrom } from '../_lib/billing.js'
import { stripe } from '../_lib/stripe.js'

const LIVE = ['active', 'trialing', 'past_due']

export function POST(request) {
  return answer(async () => {
    const user = await teacherFrom(request)
    if (!user) return json({ error: 'Sign in first.' }, 401)

    const { interval } = await request.json().catch(() => ({}))
    const price = interval === 'year' ? process.env.STRIPE_PRICE_YEARLY : process.env.STRIPE_PRICE_MONTHLY
    if (!price) throw new Error('STRIPE_PRICE_MONTHLY and STRIPE_PRICE_YEARLY must be set')

    const customer = await ensureCustomer(user)
    // ensureCustomer has just re-read Stripe, so this is current: someone
    // who already pays is not sold a second subscription.
    if (LIVE.includes((await planOf(user.id))?.status)) return json({ already: true })

    const session = await stripe('POST', '/checkout/sessions', {
      mode: 'subscription',
      customer,
      client_reference_id: user.id,
      line_items: [{ price, quantity: 1 }],
      subscription_data: { metadata: { user_id: user.id } },
      allow_promotion_codes: true,
      success_url: `${site(request)}/host?billing=done`,
      cancel_url: `${site(request)}/host?billing=cancelled`,
      // Off until Stripe Tax is set up in the dashboard; Checkout refuses to
      // open if this is asked for and it is not.
      ...(process.env.STRIPE_AUTOMATIC_TAX === '1'
        ? { automatic_tax: { enabled: true }, customer_update: { address: 'auto' } }
        : {}),
    })
    return json({ url: session.url })
  })
}
