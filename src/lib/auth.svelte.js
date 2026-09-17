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

// Where a confirmation link should land. Without this Supabase falls back to the
// project's "Site URL", which is http://localhost:3000 until someone changes it —
// so the first teacher to sign up gets bounced to a server that does not exist.
// The address still has to be on the project's redirect allow-list to be honoured.
const landing = () => `${window.location.origin}/host`

/** Resolves to true when the account still needs its email confirmed. */
export async function signUp(email, password) {
  const { data, error } = await db.auth.signUp({
    email,
    password,
    options: { emailRedirectTo: landing() },
  })
  if (error) throw new Error(error.message)
  return !data.session
}

/** A fresh confirmation link, for one that expired or was eaten by a mail scanner. */
export async function resendConfirmation(email) {
  const { error } = await db.auth.resend({
    type: 'signup',
    email,
    options: { emailRedirectTo: landing() },
  })
  if (error) throw new Error(error.message)
}

/**
 * Supabase reports a failed link by redirecting with the reason in the URL
 * fragment. Read it once and clear it, so a refresh does not replay the error.
 */
export function linkProblem() {
  const params = new URLSearchParams(window.location.hash.replace(/^#/, ''))
  if (!params.has('error')) return null
  history.replaceState(null, '', window.location.pathname + window.location.search)
  return { code: params.get('error_code') ?? params.get('error'), detail: params.get('error_description') }
}

export async function signOut() {
  await db.auth.signOut()
}
