import assert from 'node:assert/strict'
import { test } from 'node:test'

import { clockBase, remainingFraction, remainingMs, remainingSeconds } from '../src/lib/clock.js'

test('a question that has not started shows the full limit', () => {
  assert.equal(remainingMs(null, 20_000, 5_000), 20_000)
})

test('remaining time counts down and stops at zero', () => {
  assert.equal(remainingMs(1_000, 20_000, 6_000), 15_000)
  assert.equal(remainingMs(1_000, 20_000, 21_000), 0)
  assert.equal(remainingMs(1_000, 20_000, 99_000), 0)
})

test('the fraction runs from one to zero', () => {
  assert.equal(remainingFraction(1_000, 20_000, 1_000), 1)
  assert.equal(remainingFraction(1_000, 20_000, 11_000), 0.5)
  assert.equal(remainingFraction(1_000, 20_000, 30_000), 0)
})

test('displayed seconds round up, so the last second is shown as 1', () => {
  assert.equal(remainingSeconds(0, 20_000, 0), 20)
  assert.equal(remainingSeconds(0, 20_000, 19_100), 1)
  assert.equal(remainingSeconds(0, 20_000, 20_000), 0)
})

test('the countdown normally starts from the server timestamp', () => {
  const started = new Date(1_000_000).toISOString()
  assert.equal(clockBase(started, 20_000, 1_000_500), 1_000_000)
})

test('a device clock running slow falls back to when we heard about it', () => {
  // Server says the question started, but this device thinks it is 10s earlier.
  const started = new Date(1_010_000).toISOString()
  assert.equal(clockBase(started, 20_000, 1_000_000), 1_000_000)
})

test('a question left sitting past its deadline still reads zero', () => {
  // The teacher has not pressed space. This is normal, not a broken clock, so
  // the countdown must stay at the server timestamp rather than restarting.
  const started = new Date(1_000_000).toISOString()
  assert.equal(clockBase(started, 20_000, 1_090_000), 1_000_000)
  assert.equal(remainingSeconds(clockBase(started, 20_000, 1_090_000), 20_000, 1_090_000), 0)
})

test('a clock out by an absurd margin falls back', () => {
  const started = new Date(1_000_000).toISOString()
  assert.equal(clockBase(started, 20_000, 1_000_000 + 7_200_000), 1_000_000 + 7_200_000)
})

test('an unparseable timestamp falls back', () => {
  assert.equal(clockBase(null, 20_000, 555), 555)
})
