import assert from 'node:assert/strict'
import { test } from 'node:test'

import { viewFor } from '../src/lib/router.js'

test('each surface has a path', () => {
  assert.equal(viewFor('/'), 'join')
  assert.equal(viewFor('/play'), 'play')
  assert.equal(viewFor('/host'), 'host')
})

test('trailing slashes and unknown paths fall back to join', () => {
  assert.equal(viewFor('/host/'), 'host')
  assert.equal(viewFor('/nope'), 'join')
  assert.equal(viewFor(''), 'join')
})
