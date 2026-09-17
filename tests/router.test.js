import assert from 'node:assert/strict'
import { test } from 'node:test'

import { routeFor } from '../src/lib/router.js'

test('each surface has a path', () => {
  assert.deepEqual(routeFor('/'), { view: 'join' })
  assert.deepEqual(routeFor('/play'), { view: 'play' })
  assert.deepEqual(routeFor('/host'), { view: 'host' })
})

test('the wall carries its room code in the path', () => {
  assert.deepEqual(routeFor('/present/VGP2G'), { view: 'present', code: 'VGP2G' })
  assert.deepEqual(routeFor('/present/vgp2g'), { view: 'present', code: 'VGP2G' })
  assert.deepEqual(routeFor('/present'), { view: 'present', code: null })
})

test('trailing slashes and unknown paths fall back to join', () => {
  assert.deepEqual(routeFor('/host/'), { view: 'host' })
  assert.deepEqual(routeFor('/present/VGP2G/'), { view: 'present', code: 'VGP2G' })
  assert.deepEqual(routeFor('/nope'), { view: 'join' })
  assert.deepEqual(routeFor(''), { view: 'join' })
})

test('the editor lists quizzes, or opens one by id', () => {
  assert.deepEqual(routeFor('/edit'), { view: 'edit', quizId: null })
  assert.deepEqual(routeFor('/edit/22222222-2222-2222-2222-222222222222'), {
    view: 'edit',
    quizId: '22222222-2222-2222-2222-222222222222',
  })
  assert.deepEqual(routeFor('/edit/not-a-quiz-id'), { view: 'join' })
})

test('reports list games, or open one by id', () => {
  assert.deepEqual(routeFor('/games'), { view: 'games', gameId: null })
  assert.deepEqual(routeFor('/games/22222222-2222-2222-2222-222222222222'), {
    view: 'games',
    gameId: '22222222-2222-2222-2222-222222222222',
  })
  assert.deepEqual(routeFor('/games/nope'), { view: 'join' })
})

test('a malformed code is not mistaken for a room', () => {
  assert.deepEqual(routeFor('/present/way-too-long-to-be-a-code'), { view: 'join' })
})
