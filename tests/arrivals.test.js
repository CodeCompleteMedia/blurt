import assert from 'node:assert/strict'
import { test } from 'node:test'

import { BURST, arrivals } from '../src/lib/arrivals.js'

const roster = (...ids) => ids.map((id) => ({ id }))

test('the first roster sets a baseline and announces nobody', () => {
  const r = arrivals(null, roster('a', 'b', 'c'))
  assert.equal(r.baseline, true)
  assert.equal(r.arrived, 0)
  assert.equal(r.chirps, 0)
  // A projector refreshed into a full lobby must stay silent, but it still has
  // to remember who is already there.
  assert.deepEqual([...r.known].sort(), ['a', 'b', 'c'])
})

test('an arrival after the baseline is announced', () => {
  const first = arrivals(null, roster('a'))
  const second = arrivals(first.known, roster('a', 'b'))
  assert.equal(second.arrived, 1)
  assert.equal(second.chirps, 1)
})

test('nothing is announced when the roster has not changed', () => {
  const first = arrivals(null, roster('a', 'b'))
  const again = arrivals(first.known, roster('a', 'b'))
  assert.equal(again.arrived, 0)
  assert.equal(again.chirps, 0)
})

test('a score change is not an arrival', () => {
  // The roster arrives again every couple of seconds with new score values and
  // in a different order; only the ids decide.
  const first = arrivals(null, [{ id: 'a', score: 0 }, { id: 'b', score: 0 }])
  const later = arrivals(first.known, [{ id: 'b', score: 900 }, { id: 'a', score: 300 }])
  assert.equal(later.arrived, 0)
})

test('someone leaving is not an arrival', () => {
  const first = arrivals(null, roster('a', 'b', 'c'))
  const kicked = arrivals(first.known, roster('a', 'c'))
  assert.equal(kicked.arrived, 0)
  assert.deepEqual([...kicked.known].sort(), ['a', 'c'])
})

test('a swap between two polls is an arrival, even though the count held still', () => {
  // The case counting would miss: one removed, one joined, length unchanged.
  const first = arrivals(null, roster('a', 'b'))
  const swapped = arrivals(first.known, roster('a', 'c'))
  assert.equal(swapped.arrived, 1)
  assert.equal(swapped.chirps, 1)
})

test('a clump is capped, but every arrival still counts', () => {
  const first = arrivals(null, roster('a'))
  const rush = arrivals(first.known, roster('a', 'b', 'c', 'd', 'e', 'f', 'g'))
  assert.equal(rush.arrived, 6, 'all six are arrivals')
  assert.equal(rush.chirps, BURST, 'but only a few make a sound')
})

test('a whole class arriving at once does not become a whole class of noise', () => {
  const first = arrivals(null, roster())
  const everyone = arrivals(first.known, roster(...Array.from({ length: 30 }, (_, i) => `s${i}`)))
  assert.equal(everyone.arrived, 30)
  assert.ok(everyone.chirps <= BURST)
})

test('an empty or missing roster is survivable', () => {
  assert.equal(arrivals(null, []).baseline, true)
  assert.equal(arrivals(null, undefined).arrived, 0)
  assert.equal(arrivals(new Set(['a']), undefined).arrived, 0)
})
