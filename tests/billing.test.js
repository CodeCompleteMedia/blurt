import assert from 'node:assert/strict'
import { createHmac } from 'node:crypto'
import { test } from 'node:test'
import { form, pickSubscription, planRow, verifyWebhook } from '../api/_lib/stripe.js'

const secret = 'whsec_test'
const sign = (body, t, key = secret) => `t=${t},v1=${createHmac('sha256', key).update(`${t}.${body}`).digest('hex')}`

test('a webhook signed by Stripe is read', () => {
  const body = JSON.stringify({ id: 'evt_1', type: 'invoice.paid' })
  const event = verifyWebhook(body, sign(body, 1000), secret, { now: 1010 })
  assert.equal(event.id, 'evt_1')
})

test('a webhook is refused when forged, altered, stale or unsigned', () => {
  const body = JSON.stringify({ id: 'evt_1' })
  assert.throws(() => verifyWebhook(body, sign(body, 1000, 'whsec_other'), secret, { now: 1010 }), /bad signature/)
  assert.throws(() => verifyWebhook(body + ' ', sign(body, 1000), secret, { now: 1010 }), /bad signature/)
  assert.throws(() => verifyWebhook(body, sign(body, 1000), secret, { now: 2000 }), /stale/)
  assert.throws(() => verifyWebhook(body, 't=1000,v1=zz', secret, { now: 1010 }), /bad signature/)
  assert.throws(() => verifyWebhook(body, undefined, secret, { now: 1010 }), /unsigned/)
  assert.throws(() => verifyWebhook(body, sign(body, 1000), '', { now: 1010 }), /not set/)
})

test('either signature is accepted while a secret is being rolled', () => {
  const body = '{}'
  const header = `${sign(body, 1000, 'whsec_old')},v1=${sign(body, 1000).split('v1=')[1]}`
  assert.deepEqual(verifyWebhook(body, header, secret, { now: 1000 }), {})
})

test('a live subscription is preferred to a newer dead one', () => {
  const live = { id: 'sub_live', status: 'past_due', created: 1 }
  const dead = { id: 'sub_dead', status: 'incomplete_expired', created: 2 }
  assert.equal(pickSubscription([dead, live]).id, 'sub_live')
  assert.equal(pickSubscription([dead, { id: 'sub_older', status: 'canceled', created: 1 }]).id, 'sub_dead')
  assert.equal(pickSubscription([]), null)
})

test('a subscription becomes a plan row, wherever Stripe keeps the period', () => {
  const price = { recurring: { interval: 'year' } }
  const onItem = planRow({ id: 'sub_1', status: 'active', items: { data: [{ price, current_period_end: 86400 }] } })
  assert.deepEqual(onItem, {
    stripe_subscription_id: 'sub_1',
    status: 'active',
    billing_interval: 'year',
    current_period_end: '1970-01-02T00:00:00.000Z',
    cancel_at_period_end: false,
  })
  const onSubscription = planRow({ id: 'sub_1', status: 'active', current_period_end: 86400, items: { data: [{ price }] } })
  assert.equal(onSubscription.current_period_end, '1970-01-02T00:00:00.000Z')
})

test('a subscription set to end says so, whichever way it was cancelled', () => {
  const item = { price: { recurring: { interval: 'month' } }, current_period_end: 86400 }
  assert.equal(planRow({ id: 's', status: 'active', cancel_at_period_end: true, items: { data: [item] } }).cancel_at_period_end, true)
  const dated = planRow({ id: 's', status: 'active', cancel_at: 172800, items: { data: [item] } })
  assert.equal(dated.cancel_at_period_end, true)
  assert.equal(dated.current_period_end, '1970-01-03T00:00:00.000Z')
})

test('no subscription clears the row', () => {
  assert.deepEqual(planRow(null), {
    stripe_subscription_id: null,
    status: null,
    billing_interval: null,
    current_period_end: null,
    cancel_at_period_end: false,
  })
})

test('nested parameters are encoded the way Stripe reads them', () => {
  const encoded = form({ mode: 'subscription', line_items: [{ price: 'price_1', quantity: 1 }], metadata: { user_id: 'u' }, skip: undefined })
  assert.equal(
    decodeURIComponent(encoded.toString()),
    'mode=subscription&line_items[0][price]=price_1&line_items[0][quantity]=1&metadata[user_id]=u',
  )
})

test('a subscription with payment collection paused is not a paid one', () => {
  const item = { price: { recurring: { interval: 'month' } }, current_period_end: 86400 }
  const paused = planRow({ id: 's', status: 'active', pause_collection: { behavior: 'void' }, items: { data: [item] } })
  assert.equal(paused.status, 'paused')
  assert.equal(planRow({ id: 's', status: 'active', pause_collection: null, items: { data: [item] } }).status, 'active')
})
