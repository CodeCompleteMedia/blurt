// POST /api/billing/portal
//
// Sends back the address of the teacher's Stripe Customer Portal, where they
// change card, switch between monthly and yearly, see invoices, or cancel.

import { answer, json, planOf, site, teacherFrom } from '../_lib/billing.js'
import { stripe } from '../_lib/stripe.js'

export function POST(request) {
  return answer(async () => {
    const user = await teacherFrom(request)
    if (!user) return json({ error: 'Sign in first.' }, 401)

    const customer = (await planOf(user.id))?.stripe_customer_id
    if (!customer) return json({ error: 'There is no billing to manage yet.' }, 404)

    const session = await stripe('POST', '/billing_portal/sessions', {
      customer,
      return_url: `${site(request)}/host?billing=portal`,
    })
    return json({ url: session.url })
  })
}
