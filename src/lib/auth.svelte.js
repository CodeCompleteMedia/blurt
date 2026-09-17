// Who is signed in. Only a teacher ever is — this module is never loaded by the
// phone or the wall.
//
// Passwords go from the form straight to Supabase Auth; nothing in this app
// stores, logs or inspects one.

import { db } from './supabase.js'

export const auth = $state({ ready: false, user: null })

if (db) {
  db.auth.getSession().then(({ data }) => {
    auth.user = data.session?.user ?? null
    auth.ready = true
  })
  db.auth.onAuthStateChange((_event, session) => {
    auth.user = session?.user ?? null
    auth.ready = true
  })
}

export async function signIn(email, password) {
  const { error } = await db.auth.signInWithPassword({ email, password })
  if (error) throw new Error(error.message)
}

/** Resolves to true when the account still needs its email confirmed. */
export async function signUp(email, password) {
  const { data, error } = await db.auth.signUp({ email, password })
  if (error) throw new Error(error.message)
  return !data.session
}

export async function signOut() {
  await db.auth.signOut()
}
